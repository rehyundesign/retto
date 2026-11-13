// Orca 에서 띄운 세션 — 알아보기, 제목, 입력·승인 대기, 그 탭으로 데려가기.
//
// 맥 앱 macos/Sources/OrcaSessions.swift 를 옮긴 것이다. 근거와 「Orca 업데이트 때 확인할 것」은
// docs/세션-열기.md 「Orca 에서 띄운 세션」. 규칙을 바꿀 때는 Swift 쪽도 같이 고친다.
//
// 맥과 다른 점 — 맥은 Orca 의 Electron 을 node 로 따로 띄워 런타임 클라이언트를 부른다. 이 앱은 그 자체가
// Electron(node) 이라 Orca 의 runtime-client.js 를 직접 불러 쓴다. 세션 기록은 node:sqlite 로 읽기 전용으로 연다.
//
// Windows 에서 Orca 가 어디 깔리는지는 실기로 확인하지 못했다. 떠 있는 Orca.exe 의 경로로 찾고,
// 못 찾으면 electron-builder 기본 자리(%LOCALAPPDATA%\Programs\Orca)를 본다. 둘 다 없으면 Orca 기능은
// 아무것도 하지 않는다 — 대기 표시를 놓칠 뿐 엉뚱한 상태를 만들지 않는다.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ID = /^[A-Za-z0-9_:.-]{1,128}$/;
const WATCH_ACTIVE_MS = 2 * 60 * 60 * 1000;
const WATCH_DONE_MS = 10 * 60 * 1000;
const POLL_MS = 3000;

function userDataDir(platform = process.platform, home = os.homedir()) {
  if (platform === 'darwin') return path.join(home, 'Library', 'Application Support', 'orca');
  if (platform === 'win32') return process.env.APPDATA ? path.join(process.env.APPDATA, 'orca') : null;
  return path.join(process.env.XDG_CONFIG_HOME || path.join(home, '.config'), 'orca');
}

/// 떠 있는 Orca 의 Resources 폴더. 꺼져 있으면 null — 묻는 동안 Orca 를 켜지 않는다.
function runningOrcaResources(platform = process.platform) {
  try {
    if (platform === 'darwin') {
      const out = execFileSync('/usr/bin/pgrep', ['-lf', 'Orca.app/Contents/MacOS/Orca'], { encoding: 'utf8', timeout: 2000 });
      const match = /(\/\S*?Orca\.app)\/Contents\/MacOS\/Orca(\s|$)/.exec(out);
      return match ? path.join(match[1], 'Contents', 'Resources') : null;
    }
    if (platform === 'win32') {
      const out = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
        "(Get-Process -Name Orca -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path)"],
      { encoding: 'utf8', timeout: 4000, windowsHide: true }).trim();
      if (out) return path.join(path.dirname(out), 'resources');
    }
  } catch {}
  return null;
}

function installedOrcaResources(platform = process.platform) {
  const candidates = platform === 'darwin'
    ? ['/Applications/Orca.app/Contents/Resources', path.join(os.homedir(), 'Applications', 'Orca.app', 'Contents', 'Resources')]
    : platform === 'win32' && process.env.LOCALAPPDATA ? [path.join(process.env.LOCALAPPDATA, 'Programs', 'Orca', 'resources')] : [];
  return candidates.find((dir) => fs.existsSync(path.join(dir, 'app.asar.unpacked'))) || null;
}

function runtimeClientPath(resources) {
  if (!resources) return null;
  const file = path.join(resources, 'app.asar.unpacked', 'out', 'cli', 'runtime-client.js');
  return fs.existsSync(file) ? file : null;
}

/// 레토를 Orca 터미널에서 켰더라도 원격 Orca 나 다른 프로필로 가지 않게 Orca 변수를 지운다.
function forgetOrcaEnvironment(env = process.env) {
  for (const key of Object.keys(env)) if (key.startsWith('ORCA_')) delete env[key];
}

async function callOrca(clientPath, method, params) {
  forgetOrcaEnvironment();
  const { RuntimeClient } = require(clientPath);
  const client = new RuntimeClient(undefined, undefined, null, null);
  const response = await client.call(method, params);
  if (!response || response.ok === false) throw new Error(method);
  return response.result;
}

/// record_json 하나에서 마지막 Codex 스레드 ID 와 제목을 꺼낸다(orcaCodexThread).
function codexThreadFromRecord(json, sessionId) {
  let record;
  try { record = JSON.parse(json); } catch { return null; }
  const chain = Array.isArray(record?.providerHandleChain) ? record.providerHandleChain : null;
  if (!chain) return null;
  const handle = [...chain].reverse().map((link) => link && link.handle)
    .find((value) => value && value.provider === 'codex' && typeof value.threadId === 'string');
  if (!handle || !ID.test(handle.threadId)) return null;
  const name = typeof record.conversationName === 'string' ? record.conversationName.trim() : '';
  return { threadId: handle.threadId, thread: { orcaSessionId: sessionId, title: name ? [...name].slice(0, 200).join('') : null } };
}

/// 세션 기록 → { 스레드 ID: { orcaSessionId, title } }. 한 스레드를 두 채팅이 가리키면 탭 ID 를 비운다.
function readThreads(dbPath) {
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(dbPath, { readOnly: true });
  try {
    const result = {};
    const owners = {};
    for (const row of db.prepare("SELECT session_id, record_json FROM agent_session_records WHERE session_id LIKE 'codex%'").all()) {
      const found = codexThreadFromRecord(row.record_json, row.session_id);
      if (!found) continue;
      owners[found.threadId] = (owners[found.threadId] || 0) + 1;
      result[found.threadId] = found.thread;
    }
    for (const [thread, count] of Object.entries(owners)) {
      if (count > 1) result[thread] = { orcaSessionId: '', title: result[thread].title };
    }
    return result;
  } finally {
    db.close();
  }
}

/// 세션 기록을 파일이 바뀌었을 때만, 2초에 한 번까지 다시 읽는다(OrcaCodexThreadIndex).
class ThreadIndex {
  constructor(dbPath = userDataDir() && path.join(userDataDir(), 'agent-session-journal.db')) {
    this.dbPath = dbPath; this.threads = {}; this.stamp = ''; this.checkedAt = 0;
  }
  refresh(nowMs = Date.now()) {
    if (!this.dbPath || nowMs - this.checkedAt < 2000) return this.threads;
    this.checkedAt = nowMs;
    const stamp = [this.dbPath, `${this.dbPath}-wal`].map((file) => {
      try { const s = fs.statSync(file); return `${s.mtimeMs}:${s.size}`; } catch { return '0'; }
    }).join('|');
    if (stamp === this.stamp) return this.threads;
    // 못 읽으면 다음 변경 때 다시 읽는다. 제목은 잠깐 못 읽어도 바뀌지 않으므로 지난 목록을 둔다.
    try { this.threads = readThreads(this.dbPath); this.stamp = stamp; } catch {}
    return this.threads;
  }
}

/// 탭 목록 결과에서 Codex 채팅 탭을 고른다.
function codexChats(listAll) {
  const chats = [];
  for (const snapshot of listAll?.snapshots || []) {
    for (const tab of snapshot.tabs || []) {
      if (tab.type === 'agent-session' && tab.agent === 'codex' && tab.sessionId && tab.chatStatus) {
        chats.push({ sessionId: tab.sessionId, status: tab.chatStatus });
      }
    }
  }
  return chats;
}

/// 탭 상태와 앞뒤로 읽은 스레드 기록으로 { 스레드 ID: 상태 } 를 만든다(orcaChatStatuses).
/// 읽는 사이 다른 스레드로 넘어간 채팅, 두 탭이 가리키는 스레드는 버린다.
function chatStatuses(chats, before, after) {
  const result = {};
  for (const { sessionId, status } of chats) {
    const threadId = before[sessionId] && before[sessionId] === after[sessionId] ? before[sessionId] : null;
    if (!ID.test(sessionId) || !threadId || !ID.test(threadId) || typeof status.state !== 'string') continue;
    const main = status.mainAgent || {};
    const sinceMs = Number(main.state === status.state && main.stateStartedAt ? main.stateStartedAt : status.updatedAt) || 0;
    const entry = {
      orcaSessionId: sessionId,
      threadId,
      needsInput: status.state === 'blocked' || status.state === 'waiting',
      sinceMs,
      failed: status.state === 'done' && main.state === 'done' && main.outcome === 'failure',
      cancelled: status.state === 'done' && main.state === 'done' && main.outcome === 'cancellation'
    };
    result[threadId] = result[threadId] ? { ...entry, orcaSessionId: '' } : entry;
  }
  for (const key of Object.keys(result)) if (!result[key].orcaSessionId) delete result[key];
  return result;
}

/// 스레드 기록을 { Orca 세션 ID: 스레드 ID } 로.
function sessionThreads(dbPath) {
  const result = {};
  for (const [threadId, thread] of Object.entries(readThreads(dbPath))) {
    if (thread.orcaSessionId) result[thread.orcaSessionId] = threadId;
  }
  return result;
}

/// Orca 가 알려 준 채팅 상태를 화면 상태에 겹친다(applyOrcaChatStatus).
/// turnStartedAtMs 는 롤아웃의 마지막 사용자 요청 시각이다. 실패·취소 뒤 새 턴이 시작됐는지 이것으로 본다 —
/// 롤아웃 파일 시각은 실패·취소 기록을 쓰는 순간에도 바뀌어 근거가 되지 못한다.
function applyChatStatus(chat, session, turnStartedAtMs = 0) {
  if (!chat) return session;
  const result = { ...session };
  if (!result.orcaSessionId) result.orcaSessionId = chat.orcaSessionId;
  const newTurn = (turnStartedAtMs || 0) > chat.sinceMs;
  if (chat.cancelled) {
    // 멈춘 턴은 롤아웃에 완료가 남지 않아 작업 중으로 보인다. 쉬는 중으로 내린다.
    if (newTurn || !['running', 'review', 'waiting'].includes(result.state)) return result;
    return { ...result, state: 'idle', needsAttention: false, updatedAtMs: chat.sinceMs || result.updatedAtMs, stateSource: 'orca' };
  }
  if (chat.failed) {
    // 실패 뒤 새 턴이 시작됐으면 지난 실패를 다시 띄우지 않는다.
    if (newTurn) return result;
    return { ...result, state: 'failed', needsAttention: true, updatedAtMs: chat.sinceMs || result.updatedAtMs, stateSource: 'orca' };
  }
  // 롤아웃 완료가 더 새로워도 대기를 버리지 않는다. Orca 는 내 답을 기다리며 끝난 턴도 blocked 로 낸다.
  if (!chat.needsInput) return result;
  return { ...result, state: 'waiting', needsAttention: true, updatedAtMs: chat.sinceMs || result.updatedAtMs, stateSource: 'orca' };
}

/// Orca 에 물어볼 채팅인가(orcaChatNeedsWatching). 화면 상태가 아니라 원래 상태와 마지막 활동으로 고른다.
function needsWatching(state, lastActivityMs, nowMs) {
  if (!lastActivityMs || lastActivityMs <= 0) return false;
  const age = nowMs - lastActivityMs;
  if (['running', 'review', 'waiting', 'jumping'].includes(state)) return age <= WATCH_ACTIVE_MS;
  if (state === 'waving') return age <= WATCH_DONE_MS;
  return false;
}

/// 롤아웃 task 를 Orca 채팅으로 표시하고 탭 ID 를 붙인다(linkOrcaCodexTask).
function linkTask(task, thread) {
  if (!thread || (task.source !== 'codex' && task.client !== 'codex')) return task;
  const result = { ...task, orcaHosted: true };
  if (thread.orcaSessionId && !result.orcaSessionId) result.orcaSessionId = thread.orcaSessionId;
  return result;
}

function isOrcaSession(session) {
  return session.client === 'orca' || session.orcaHosted === true || Boolean(session.orcaSessionId) || Boolean(session.orcaTerminalHandle);
}

/// 작업 중인 Orca 의 Codex 채팅만 3초마다 묻는다(OrcaChatStatusReader).
class ChatStatusReader {
  constructor({ onChange, dbPath } = {}) {
    this.onChange = onChange || (() => {});
    this.dbPath = dbPath || (userDataDir() && path.join(userDataDir(), 'agent-session-journal.db'));
    this.statuses = {};
    this.failures = {};
    this.tracked = new Set();
    this.timer = null;
    this.inFlight = false;
  }

  status(threadId) { return this.statuses[threadId] || this.failures[threadId]; }

  track(threadIds) {
    this.tracked = new Set(threadIds);
    if (this.tracked.size === 0) {
      this.stop();
      this.publish({});
      return;
    }
    this.publish(Object.fromEntries(Object.entries(this.statuses).filter(([id]) => this.tracked.has(id))));
    if (this.timer) return;
    this.timer = setInterval(() => this.poll(), POLL_MS);
    this.poll();
  }

  stop() { clearInterval(this.timer); this.timer = null; }

  async poll() {
    if (this.inFlight) return;
    const clientPath = runtimeClientPath(runningOrcaResources());
    if (!clientPath || !this.dbPath) { this.publish({}); return; }
    this.inFlight = true;
    let result = null;
    try {
      const before = sessionThreads(this.dbPath);
      const listed = await callOrca(clientPath, 'session.tabs.listAll', {});
      result = chatStatuses(codexChats(listed), before, sessionThreads(this.dbPath));
    } catch {}
    this.inFlight = false;
    if (result) this.remember(result);
    // 못 읽었으면 지난 값을 들고 있지 않는다. 승인이 끝났는데 파란색이 남는 것보다 롤아웃 상태로 돌아가는 편이 낫다.
    this.publish(Object.fromEntries(Object.entries(result || {}).filter(([id]) => this.tracked.has(id))));
  }

  remember(result) {
    const next = { ...this.failures };
    for (const [thread, status] of Object.entries(result)) {
      if (status.failed || status.cancelled) next[thread] = status; else delete next[thread];
    }
    const entries = Object.entries(next).sort((a, b) => b[1].sinceMs - a[1].sinceMs).slice(0, 256);
    const trimmed = Object.fromEntries(entries);
    if (JSON.stringify(trimmed) === JSON.stringify(this.failures)) return;
    this.failures = trimmed;
    this.onChange();
  }

  publish(next) {
    if (JSON.stringify(next) === JSON.stringify(this.statuses)) return;
    this.statuses = next;
    this.onChange();
  }
}

/// 그 세션의 탭으로 간다(orcaRevealScript). 결과는 'chat' · 'terminal' · 'workspace' · 'app' · 'unavailable'.
async function reveal({ sessionId, terminalHandle, workspacePath, agent, codexThreadId }) {
  const resources = runningOrcaResources() || installedOrcaResources();
  const clientPath = runtimeClientPath(resources);
  if (!clientPath) return 'unavailable';
  const pathOf = (worktree) => String(worktree || '').split('::').slice(1).join('::');
  const same = (a, b) => process.platform === 'win32' ? String(a).toLowerCase() === String(b).toLowerCase() : a === b;
  try {
    // 터미널 탭. 공개 CLI 의 `orca terminal switch` 가 부르는 요청과 같다.
    if (terminalHandle) {
      const focused = await callOrca(clientPath, 'terminal.focus', { terminal: terminalHandle, navigation: 'host' }).then(() => true, () => false);
      if (focused) return 'terminal';
    }
    const snapshots = (await callOrca(clientPath, 'session.tabs.listAll', {}))?.snapshots || [];
    const chats = [];
    for (const snapshot of snapshots) {
      for (const tab of snapshot.tabs || []) {
        if (tab.type === 'agent-session' && tab.sessionId) chats.push({ worktree: snapshot.worktree, tabId: tab.id, sessionId: tab.sessionId, agent: tab.agent });
      }
    }
    let chat = sessionId ? chats.find((item) => item.sessionId === sessionId) : undefined;
    if (!chat && !sessionId && codexThreadId) {
      const dbPath = userDataDir() && path.join(userDataDir(), 'agent-session-journal.db');
      let owners = [];
      try {
        const threads = sessionThreads(dbPath);
        owners = chats.filter((item) => item.agent === 'codex' && threads[item.sessionId] === codexThreadId);
      } catch {}
      if (owners.length === 1) chat = owners[0];
    }
    if (!chat && !sessionId && workspacePath) {
      const candidates = chats.filter((item) => same(pathOf(item.worktree), workspacePath) && (!agent || item.agent === agent));
      // 같은 워크스페이스에 같은 종류 채팅이 여럿이면 어느 것인지 모른다. 워크스페이스까지만 연다.
      if (candidates.length === 1) chat = candidates[0];
    }
    if (!chat) {
      const workspace = snapshots.find((snapshot) => same(pathOf(snapshot.worktree), workspacePath));
      if (!workspace) return 'app';
      await callOrca(clientPath, 'worktree.activate', { worktree: `id:${workspace.worktree}`, navigation: 'host' });
      return 'workspace';
    }
    const worktree = `id:${chat.worktree}`;
    await callOrca(clientPath, 'worktree.activate', { worktree, navigation: 'host' });
    await callOrca(clientPath, 'session.tabs.activate', { worktree, tabId: chat.tabId, navigation: 'host', intent: 'user' });
    return 'chat';
  } catch {
    return 'app';
  }
}

function openRequest(session) {
  if (!isOrcaSession(session) || session.source === 'slack') return null;
  const codex = session.source === 'codex' || session.client === 'codex';
  return {
    sessionId: session.orcaSessionId || null,
    terminalHandle: session.orcaTerminalHandle || null,
    workspacePath: session.cwd || null,
    agent: codex ? 'codex' : 'claude',
    codexThreadId: session.orcaHosted ? (session.rawSessionId || null) : null
  };
}

module.exports = {
  ChatStatusReader,
  ThreadIndex,
  applyChatStatus,
  chatStatuses,
  codexChats,
  codexThreadFromRecord,
  forgetOrcaEnvironment,
  isOrcaSession,
  linkTask,
  needsWatching,
  openRequest,
  readThreads,
  reveal,
  runningOrcaResources,
  runtimeClientPath,
  userDataDir
};
