// 훅이 적은 세션을 읽고 무엇을 보여 줄지 정한다. 화면과 OS 에 기대지 않는 부분만 모았다.
//
// 맥 앱의 macos/Sources/Sessions.swift · Tones.swift · AppDelegate.swift(applySessions) 를 옮긴 것이다.
// 값이 갈리면 두 앱이 같은 세션을 다르게 보여 주므로, 숫자·순서를 바꿀 때는 Swift 쪽도 같이 고친다.

const STATES = ['idle', 'running', 'review', 'waiting', 'failed', 'waving', 'jumping', 'sleeping'];

/// 전부 회색인 채로 이만큼 지나면 레토도 잔다(Sessions.swift sleepAfter).
const SLEEP_AFTER_MS = 600 * 1000;
/// 다 끝내 놓고 아무도 보러 오지 않은 채 이만큼 지나면 그림만 존다(dozeAfter).
const DOZE_AFTER_MS = 1800 * 1000;
/// 작업 중이라고 적혀 있는데 이만큼 소식이 없으면 유령이다(staleWorkingTimeout).
const STALE_WORKING_MS = 600 * 1000;
/// 앱이 켜지기 이만큼 전에 끝난 일은 읽음으로 넘긴다(trackingGrace).
const TRACKING_GRACE_MS = 1800 * 1000;
/// 이름표로 받아들일 최소 길이. hook.cjs 의 NAME_MIN 과 같은 값이어야 한다.
const NAME_MIN = 4;

const NEEDS_INPUT = new Set(['waiting', 'failed', 'waving']);

// 이름표 색. 글자 대비 4.5:1 을 맞춘 값이다(Tones.swift 주석).
const TONES = {
  working: { background: '#73DF5D', text: '#0A5225' },
  needsYou: { background: '#0174E3', text: '#FFFFFF' },
  done: { background: '#F06200', text: '#441C00' },
  failed: { background: '#DC0714', text: '#FFF499' },
  quiet: { background: '#757575', text: '#FFFFFF' },
  // Slack 새 메시지는 보라색(Tones.swift toneSlack).
  slack: { background: '#7C3AED', text: '#FFFFFF' }
};

/// 아틀라스 한 칸은 224×240, 행 12 개다(Geometry.swift SpriteSheetLayout.retto).
const SPRITE = { cellWidth: 224, cellHeight: 240, rows: 12 };

const ANIMATIONS = {
  idle: { row: 0, frames: 6, interval: 0.23, cycleLimit: null, kicker: 'RESTING', title: '조용히 곁을 지키는 중', tone: 'quiet' },
  running: { row: 7, frames: 6, interval: 0.125, cycleLimit: null, kicker: 'THINKING', title: 'AI가 생각중…', tone: 'working' },
  review: { row: 8, frames: 6, interval: 0.155, cycleLimit: null, kicker: 'USING A TOOL', title: '도구를 쓰는 중', tone: 'working' },
  waiting: { row: 6, frames: 6, interval: 0.31, cycleLimit: null, kicker: 'NEEDS YOU', title: '네 결정을 기다리는 중', tone: 'needsYou' },
  failed: { row: 5, frames: 8, interval: 0.18, cycleLimit: null, kicker: 'OOPS', title: '잠깐 발이 꼬였어', tone: 'failed' },
  waving: { row: 3, frames: 4, interval: 0.185, cycleLimit: 2, kicker: 'DONE', title: '다 했어! 잘했어', tone: 'done' },
  jumping: { row: 4, frames: 5, interval: 0.15, cycleLimit: null, kicker: "LET'S GO", title: '시작해 볼까?', tone: 'working' },
  sleeping: { row: 11, frames: 6, interval: 0.46, cycleLimit: null, kicker: 'ZZZ', title: '쿨쿨 자는 중', tone: 'quiet' }
};

function petState(value) {
  return STATES.includes(value) ? value : 'idle';
}

function isSeen(updatedAtMs, seenAtMs) {
  if (seenAtMs == null) return false;
  return seenAtMs >= (updatedAtMs || 0);
}

function isStaleWorking(state, updatedAtMs, nowMs) {
  if (state !== 'running' && state !== 'review' && state !== 'jumping') return false;
  if (!updatedAtMs || updatedAtMs <= 0) return false;
  return nowMs - updatedAtMs > STALE_WORKING_MS;
}

/// 화면에 그릴 상태. 읽은 알림은 내려놓고, 소식이 끊긴 작업 중은 조용한 상태로 본다.
/// 트랜스크립트가 자란 시각도 소식으로 친다 — 도구 없이 오래 생각하는 세션을 유령으로 몰지 않으려고.
function displayState(state, updatedAtMs, seenAtMs, transcriptModifiedAtMs, nowMs) {
  if (NEEDS_INPUT.has(state) && isSeen(updatedAtMs, seenAtMs)) return 'idle';
  const lastActivity = Math.max(updatedAtMs || 0, transcriptModifiedAtMs || 0);
  if (isStaleWorking(state, lastActivity, nowMs)) return 'idle';
  return state;
}

/// 맥 앱 Sessions.swift selectionPriority 와 같은 값. 입력 대기 → 실패 → Slack 새 메시지 → 완료 → 작업 중.
function selectionPriority(state, isClosed, source) {
  if (isClosed) return -100;
  if (source === 'slack' && state === 'waving') return 70;
  return { waiting: 80, failed: 75, waving: 55, running: 40, review: 35, jumping: 20, idle: 10, sleeping: 0 }[state] ?? 0;
}

function shouldSleep(newestUpdatedAtMs, nowMs, hasBusySession) {
  if (hasBusySession || !newestUpdatedAtMs || newestUpdatedAtMs <= 0) return false;
  return nowMs - newestUpdatedAtMs > SLEEP_AFTER_MS;
}

function shouldDozeWhileWaiting(newestAttentionAtMs, nowMs, everythingDone) {
  if (!everythingDone || !newestAttentionAtMs || newestAttentionAtMs <= 0) return false;
  return nowMs - newestAttentionAtMs > DOZE_AFTER_MS;
}

function isAncientNews(updatedAtMs, trackingStartedAtMs) {
  if (!updatedAtMs || updatedAtMs <= 0) return false;
  return updatedAtMs < trackingStartedAtMs - TRACKING_GRACE_MS;
}

/// sessions.json 한 칸을 화면이 쓰는 모양으로 바꾼다.
function normalizeSession(id, raw) {
  const record = raw && typeof raw === 'object' ? raw : {};
  const parsed = Date.parse(record.updatedAt || '');
  return {
    ...record,
    id: record.sessionId || id,
    state: petState(record.state),
    updatedAtMs: Number.isFinite(parsed) ? parsed : (typeof record.updatedAtMs === 'number' ? record.updatedAtMs : undefined),
    isClosed: record.closed === true,
    needsAttention: record.attention === true && record.closed !== true
  };
}

function readRegistry(text) {
  let parsed;
  try { parsed = JSON.parse(text); } catch { return null; }
  const sessions = parsed && typeof parsed.sessions === 'object' && parsed.sessions ? parsed.sessions : {};
  return Object.entries(sessions).map(([id, raw]) => normalizeSession(id, raw));
}

function sourceLabel(session) {
  return session.source === 'codex' || session.client === 'codex' ? 'Codex' : 'Claude';
}

function projectName(session) {
  if (session.projectName) return session.projectName;
  if (session.cwd) {
    const parts = String(session.cwd).split(/[\\/]/).filter(Boolean);
    if (parts.length) return parts[parts.length - 1];
  }
  return sourceLabel(session) === 'Codex' ? 'Codex' : 'Claude Code';
}

/// 이름표에는 확인된 제목만 쓴다. 짧은 답("B")이 굳은 displayTitle 은 이름으로 쓰지 않는다.
function sessionTitle(session) {
  if (session.sessionTitle) return session.sessionTitle;
  if (session.activeTaskSubject) return session.activeTaskSubject;
  if (session.displayTitle && session.displayTitle.trim().length >= NAME_MIN) return session.displayTitle;
  return 'No name';
}

function menuLabel(session) {
  if (session.source === 'slack') return `● 새 메시지  ${sessionTitle(session).slice(0, 42)} · Slack`;
  const mark = {
    waiting: '● 기다림',
    failed: '● 실패',
    running: '● 작업 중',
    review: '● 작업 중',
    waving: '● 완료'
  }[session.state] || '○ 쉬는 중';
  const isOrca = session.client === 'orca' || session.orcaHosted === true || Boolean(session.orcaSessionId) || Boolean(session.orcaTerminalHandle);
  const origin = isOrca ? ' · Orca' : {
    vscode: ' · VS Code',
    claude: ' · Claude 앱',
    cli: ' · Claude Code CLI',
    codex: ' · Codex'
  }[session.client] ?? (sourceLabel(session) === 'Codex' ? ' · Codex' : '');
  return `${mark}  ${sessionTitle(session).slice(0, 42)} · ${projectName(session)}${origin}`;
}

/// 무엇을 보여 줄지 고른다. 맥 앱 applySessions 와 같은 순서다.
///
/// - 우선순위: 입력 대기 → 완료 → 실패 → 작업 중 → 도구 → 시작 → 쉬는 중
/// - 고정한 세션이 있어도 손이 필요한 세션이 생기면 그쪽을 먼저 보여 준다
/// - 배지는 「답변이 끝났는데 아직 안 본」 세션만 센다. 대기·실패는 이름표 색이 이미 말한다
function chooseView({ sessions, seen, pinnedId, nowMs, trackingStartedAtMs, transcriptModifiedAt = () => undefined }) {
  const newlySeen = {};
  const seenAt = (id) => newlySeen[id] ?? seen[id];
  const effective = (session) => displayState(session.state, session.updatedAtMs, seenAt(session.id), transcriptModifiedAt(session), nowMs);
  const needsAttention = (session) => {
    if (!session.needsAttention) return false;
    if (isSeen(session.updatedAtMs, seenAt(session.id))) return false;
    if (seenAt(session.id) == null && isAncientNews(session.updatedAtMs, trackingStartedAtMs)) {
      newlySeen[session.id] = Math.max(session.updatedAtMs || 0, nowMs);
      return false;
    }
    return true;
  };

  // 오래된 소식을 읽음으로 넘기는 판정을 먼저 한다. 그래야 같은 틱의 그림·잠에도 반영된다(맥 앱과 같다).
  for (const session of sessions) if (!session.isClosed) needsAttention(session);
  const sorted = sessions
    .map((session) => ({ ...session, visibleState: effective(session) }))
    .sort((left, right) => {
      const diff = selectionPriority(right.visibleState, right.isClosed, right.source) - selectionPriority(left.visibleState, left.isClosed, left.source);
      return diff !== 0 ? diff : (right.updatedAtMs || 0) - (left.updatedAtMs || 0);
    });
  const open = sorted.filter((session) => !session.isClosed);
  const attention = open.filter(needsAttention);

  let selected;
  let keepPin = false;
  const pinned = pinnedId ? open.find((session) => session.id === pinnedId) : undefined;
  if (pinned) {
    keepPin = true;
    selected = needsAttention(pinned) ? pinned : (attention[0] || pinned);
  } else {
    selected = open[0] || sorted[0];
  }

  const badge = open.filter((session) => needsAttention(session) && session.visibleState === 'waving');
  const asleep = shouldSleep(
    Math.max(0, ...open.map((session) => session.updatedAtMs || 0)) || undefined,
    nowMs,
    open.some((session) => session.visibleState !== 'idle')
  );
  const dozing = !asleep && shouldDozeWhileWaiting(
    Math.max(0, ...badge.map((session) => session.updatedAtMs || 0)) || undefined,
    nowMs,
    badge.length > 0 && open.every((session) => session.visibleState === 'idle' || session.visibleState === 'waving')
  );

  let pose;
  if (!selected) pose = 'sleeping';
  else if (asleep || dozing) pose = 'sleeping';
  else pose = selected.visibleState;

  return {
    selected,
    sessions: sorted,
    pose,
    asleep,
    dozing,
    badgeCount: badge.length,
    badgeSessions: badge,
    keepPin,
    newlySeen
  };
}

/// `C:\work\c#app` → `vscode://file/C:/work/c%23app/`. 조각마다 인코딩해야 `#`·`?` 가 경로로 남는다.
function vscodeFolderUrl(cwd) {
  const parts = String(cwd).replaceAll('\\', '/').split('/');
  const encoded = parts.map((part, index) => (index === 0 && /^[A-Za-z]:$/.test(part) ? part : encodeURIComponent(part))).join('/');
  return `vscode://file${encoded.startsWith('/') ? '' : '/'}${encoded}/`;
}

module.exports = {
  ANIMATIONS,
  NAME_MIN,
  SPRITE,
  STATES,
  TONES,
  chooseView,
  displayState,
  isAncientNews,
  isSeen,
  menuLabel,
  normalizeSession,
  projectName,
  readRegistry,
  selectionPriority,
  sessionTitle,
  shouldDozeWhileWaiting,
  shouldSleep,
  sourceLabel,
  vscodeFolderUrl
};
