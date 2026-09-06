const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const VALID_STATES = new Set(['idle', 'running', 'review', 'waiting', 'failed', 'waving', 'jumping']);
const chunks = [];
const petDir = __dirname;
const registryPath = path.join(petDir, 'sessions.json');
/// 세션 이름표로 받아들일 최소 길이. 첫 요청이라도 이보다 짧으면 이름으로 쓰지 않는다.
const NAME_MIN = 4;
const legacyStatePath = path.join(petDir, 'state.json');
const lockPath = path.join(petDir, '.sessions.lock');
const sleepArray = new Int32Array(new SharedArrayBuffer(4));
const eventSource = process.argv[3] === 'codex' ? 'codex' : 'claude';

function text(value, limit = 180) {
  if (!value) return '';
  const normalized = String(value).replace(/\s+/g, ' ').trim();
  return normalized.length > limit ? `${normalized.slice(0, limit - 1)}…` : normalized;
}

function normalizeError(value) {
  if (!value) return '';
  if (typeof value === 'string') return text(value);
  if (typeof value.message === 'string') return text(value.message);
  try { return text(JSON.stringify(value)); } catch { return text(value); }
}

function basename(cwd) {
  if (!cwd) return eventSource === 'codex' ? 'Codex' : 'Claude Code';
  return path.basename(cwd) || cwd;
}

function readJSON(filePath, fallback) {
  try { return JSON.parse(fs.readFileSync(filePath, 'utf8')); } catch { return fallback; }
}

function writeJSONAtomic(filePath, value) {
  const tempPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tempPath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  fs.renameSync(tempPath, filePath);
}

function withRegistryLock(callback) {
  fs.mkdirSync(petDir, { recursive: true });
  let acquired = false;
  // 5ms 씩 600번 = 3초. 훅 등록에 걸어 둔 timeout 5초 안에 들어간다.
  // 짧게 잡았다가 검사에서 한 번 놓쳤다 — 잠금을 못 잡으면 조용히 그냥 돌아가므로,
  // 부하가 몰릴 때 상태 한 칸이 소리 없이 사라진다. 기다리는 편이 낫다.
  for (let attempt = 0; attempt < 600; attempt += 1) {
    try {
      fs.mkdirSync(lockPath);
      acquired = true;
      break;
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      try {
        if (Date.now() - fs.statSync(lockPath).mtimeMs > 10_000) {
          fs.rmSync(lockPath, { recursive: true, force: true });
        }
      } catch {}
      Atomics.wait(sleepArray, 0, 0, 5);
    }
  }
  if (!acquired) return;
  try { callback(); } finally { fs.rmSync(lockPath, { recursive: true, force: true }); }
}

function eventState(input, fallback) {
  const event = input.hook_event_name || input.hookEventName || '';
  const notificationType = input.notification_type || '';
  const toolName = input.tool_name || '';
  switch (event) {
    case 'SessionStart': return input.source === 'resume' ? 'jumping' : 'idle';
    case 'UserPromptSubmit': return 'running';
    case 'PreToolUse':
      return /^(Read|Grep|Glob|WebFetch|WebSearch|LS|NotebookRead)$/i.test(toolName) ? 'review' : 'running';
    case 'PostToolUse':
      if (eventSource === 'codex' && toolResponseFailed(input.tool_response)) return 'failed';
      return 'running';
    case 'PostToolBatch':
    case 'SubagentStart':
    case 'SubagentStop':
    case 'TaskCreated': return 'running';
    case 'TaskCompleted': return 'review';
    case 'PermissionRequest':
    case 'Elicitation': return 'waiting';
    case 'Notification':
      return /permission_prompt|agent_needs_input|elicitation_dialog/i.test(notificationType) ? 'waiting' : 'idle';
    case 'PostToolUseFailure':
    case 'PermissionDenied':
    case 'StopFailure': return 'failed';
    case 'Stop':
      // 답변이 끝났으면 완료다. 백그라운드 작업이 남아 있어도 화면의 답은 이미 읽을 수 있고,
      // 그걸 "작업 중" 으로 두면 완료 배지가 영원히 안 뜬다. 개수는 backgroundTaskCount 로 남긴다.
      return 'waving';
    case 'SessionEnd': return 'idle';
    default: return VALID_STATES.has(fallback) ? fallback : 'idle';
  }
}

function toolResponseFailed(response) {
  if (!response || typeof response !== 'object') return false;
  if (response.isError === true || response.is_error === true) return true;
  const exitCode = response.exit_code ?? response.exitCode ?? response.termination_status;
  return typeof exitCode === 'number' && exitCode !== 0;
}

/// Claude Code 는 세션 타이틀을 트랜스크립트에 적어 둔다.
///   custom-title : 사용자가 직접 바꾼 이름 (가장 우선)
///   ai-title     : Claude 가 붙인 이름
/// 타이틀이 바뀔 때마다 새 줄이 덧붙으므로 파일 끝 256KB 만 읽어도 최신값이 잡힌다.
/// 훅은 도구 호출마다 돌기 때문에 전체를 읽지 않는다.
function sessionTitleFrom(transcriptPath) {
  if (!transcriptPath) return '';
  let fd;
  try {
    fd = fs.openSync(transcriptPath, 'r');
    const size = fs.fstatSync(fd).size;
    const span = Math.min(size, 262144);
    const buffer = Buffer.alloc(span);
    fs.readSync(fd, buffer, 0, span, size - span);
    let aiTitle = '';
    let customTitle = '';
    for (const line of buffer.toString('utf8').split('\n')) {
      if (!line.includes('-title')) continue;
      try {
        const record = JSON.parse(line);
        // 이름을 지워 AI 이름으로 되돌리면 빈 custom-title 이 적힌다. 그때도 따라가야 한다.
        // 빈 값을 무시하면 한번 붙인 사용자 이름이 영원히 남는다.
        if (record.type === 'custom-title') customTitle = record.customTitle || '';
        else if (record.type === 'ai-title' && record.aiTitle) aiTitle = record.aiTitle;
      } catch {}
    }
    return text(customTitle || aiTitle, 80);
  } catch {
    return '';
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch {} }
  }
}

/// 트랜스크립트 끝에서 Claude 가 가장 최근에 쓴 문장을 집는다.
/// assistant 레코드의 message.content 안 text 블록이 그것이고, 도구를 부를 때마다 새로 쌓이므로
/// 훅이 돌 때마다 값이 갱신된다 — 그래서 펫 말풍선이 "지금 하는 말" 을 따라간다.
/// 두 클라이언트는 같은 말을 다른 모양으로 적는다. 한쪽 모양만 읽으면
/// 다른 쪽 세션의 말풍선이 통째로 비어 "생각중" 에 머문다.
///   Claude : {"type":"assistant","message":{"content":[{"type":"text","text":…}]}}
///   Codex  : {"type":"response_item","payload":{"type":"message","role":"assistant",
///                                               "content":[{"type":"output_text","text":…}]}}
/// Codex 의 `event_msg:agent_message` 도 같은 문장을 담지만 도구 결과까지 섞여 들어와 쓰지 않는다.
function assistantTextIn(record) {
  if (!record || typeof record !== 'object') return '';
  let message;
  if (record.type === 'assistant') message = record.message;
  else if (record.type === 'response_item'
    && record.payload
    && record.payload.type === 'message'
    && record.payload.role === 'assistant') message = record.payload;
  const content = message && message.content;
  if (!Array.isArray(content)) return '';
  return content
    .filter((block) => block
      && (block.type === 'text' || block.type === 'output_text')
      && typeof block.text === 'string')
    .map((block) => block.text)
    .join(' ')
    .trim();
}

/// Codex 세션의 이름. Claude 와 달리 롤아웃 파일에는 이름 줄이 없고,
/// Codex 가 따로 `session_index.jsonl` 에 스레드 이름을 적어 둔다(이름이 붙은 스레드만 올라온다).
/// 이걸 안 읽으면 이름표가 첫 프롬프트로 떨어져, 레토가 내 말을 되돌려 주는 것처럼 읽힌다.
/// 이름은 자주 바뀌지 않으므로 끝 64KB 만 보고 마지막에 적힌 값을 쓴다.
function codexThreadNameFrom(threadId) {
  if (!threadId) return '';
  const home = process.env.CODEX_HOME || path.join(os.homedir(), '.codex');
  const indexPath = path.join(home, 'session_index.jsonl');
  let fd;
  try {
    fd = fs.openSync(indexPath, 'r');
    const size = fs.fstatSync(fd).size;
    const span = Math.min(size, 65536);
    const buffer = Buffer.alloc(span);
    fs.readSync(fd, buffer, 0, span, size - span);
    let name = '';
    for (const line of buffer.toString('utf8').split('\n')) {
      if (!line.includes(threadId)) continue;
      try {
        const record = JSON.parse(line);
        if (record.id === threadId && record.thread_name) name = record.thread_name;
      } catch {}
    }
    return text(name, 80);
  } catch {
    return '';
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch {} }
  }
}

function lastAssistantTextFrom(transcriptPath) {
  if (!transcriptPath) return '';
  let fd;
  try {
    fd = fs.openSync(transcriptPath, 'r');
    const size = fs.fstatSync(fd).size;
    const span = Math.min(size, 524288);
    const buffer = Buffer.alloc(span);
    fs.readSync(fd, buffer, 0, span, size - span);
    let latest = '';
    for (const line of buffer.toString('utf8').split('\n')) {
      if (!line.includes('"assistant"')) continue;
      let record;
      try { record = JSON.parse(line); } catch { continue; }
      const text = assistantTextIn(record);
      if (text) latest = text;
    }
    return text_(latest);
  } catch {
    return '';
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch {} }
  }
}

function text_(value) { return text(value, 400); }

/// 이 세션이 어느 클라이언트에서 도는지. 훅은 Claude Code 프로세스의 자식이라
/// `CLAUDE_CODE_ENTRYPOINT` 를 그대로 물려받는다. 오버레이가 이 값으로 클릭했을 때 띄울 앱을 정한다.
///   `claude-vscode`  → VS Code 확장
///   `claude-desktop` → Claude 데스크탑 앱. 실측값이다 — 앱 번들 코드만 읽으면 SDK 기본값 `sdk-ts` 로
///                      떨어질 것 같지만, 실제로 돌려 보면 이 값을 박는다
///   `cli`            → 터미널. 돌아가는 세션을 되살릴 방법이 없어서 VS Code 로 보낸다
/// 처음에는 `CLAUDE_CODE_EXECPATH` 에 `.vscode` 가 있는지도 봤는데, 그건 Cursor 같은 포크를 가려내려던
/// 것이었다. 포크를 빼기로 하면서 쓸모가 없어졌고, 실제 데스크탑 세션을 VS Code 로 오분류하기까지 했다.
/// 이름을 모르는 새 호스트는 VS Code 가 아닌 쪽으로 본다 — VS Code 만이 이름으로 확실히 가려진다.
function detectClient() {
  const entrypoint = String(process.env.CLAUDE_CODE_ENTRYPOINT || '');
  if (!entrypoint) return '';
  if (entrypoint === 'cli') return 'cli';
  return entrypoint.includes('vscode') ? 'vscode' : 'claude';
}

/// SessionStart 는 "이 세션에 프로세스가 붙었다" 는 뜻이지 "상태가 바뀌었다" 가 아니다.
///
/// VS Code 는 세션마다 claude 프로세스를 물고 있어서 SessionStart 가 한 번만 온다.
/// Claude 데스크탑 앱은 턴마다 프로세스를 새로 띄웠다 내려서, `Stop` 2초 뒤에 `SessionStart(resume)`
/// 이 또 온다. 그대로 받으면 `waving`(완료)이 `jumping` 으로 내려앉는다 — 우선순위가
/// jumping 20 < running 40 < waving 55 라 그 세션이 목록 바닥으로 내려가고, 완료 배지가 2초 만에
/// 사라지고 다음 턴의 "생각중" 도 곧바로 덮인다. 클로드 앱에서 레토가 멍하니 있던 이유가 이것이다.
///
/// 그래서 최근까지 소식이 있던 세션에는 SessionStart 가 상태도 시각도 건드리지 않는다.
/// 진짜 오랜만에 되살린 세션(그리고 이미 닫힌 세션)만 `jumping` 으로 반긴다.
const sessionStartGrace = 120_000;

function isLiveRestart(event, previous, nowMs) {
  return event === 'SessionStart'
    && Boolean(previous.state)
    && previous.closed !== true
    && nowMs - (previous.updatedAtMs || 0) < sessionStartGrace;
}

/// 클로드 앱은 창을 띄우거나 폴더를 훑을 때마다 프롬프트 한 번 없이 SessionStart→SessionEnd 만
/// 남기고 사라지는 세션을 만든다(1초 안에 나고 죽는다). 그대로 두면 레지스트리가 껍데기로 찬다.
/// 사람이 말을 건 적도 Claude 가 답한 적도 없이 끝난 세션은 기록에 남기지 않는다.
function isGhost(record) {
  return record.closed === true
    && !record.promptedAt
    && !record.sessionTitle
    && !record.lastAssistantMessage;
}

function attentionFor(state, event) {
  if (event === 'SessionEnd') return false;
  return state === 'waiting' || state === 'failed' || state === 'waving';
}

function updateRegistry(input, fallbackState) {
  const now = new Date();
  const nowMs = now.getTime();
  const event = input.hook_event_name || input.hookEventName || '';
  const rawSessionId = text(input.session_id, 200) || `unknown-${process.ppid}`;
  // Claude와 Codex가 우연히 같은 id를 써도 서로 덮지 않는다. 기존 Claude 레코드는
  // 호환을 위해 예전 UUID를 그대로 두고 Codex 쪽만 접두어를 붙인다.
  const sessionId = eventSource === 'codex' ? `codex:${rawSessionId}` : rawSessionId;
  const registry = readJSON(registryPath, { version: 1, sessions: {} });
  registry.version = 1;
  registry.sessions = registry.sessions && typeof registry.sessions === 'object' ? registry.sessions : {};
  const previous = registry.sessions[sessionId] || {};
  const liveRestart = isLiveRestart(event, previous, nowMs);
  const state = liveRestart ? previous.state : eventState(input, fallbackState);
  const cwd = text(input.cwd, 500) || previous.cwd || '';
  const prompt = text(input.prompt, 80);
  const taskSubject = text(input.task_subject || input.subject, 100);
  const lastAssistantMessage = text(input.last_assistant_message, 400);
  const error = normalizeError(input.error || input.error_type || input.message
    || (toolResponseFailed(input.tool_response) ? input.tool_response : ''));
  const backgroundTaskCount = Array.isArray(input.background_tasks) ? input.background_tasks.length : 0;
  // 이름표에 쓸 프롬프트인가. 기준은 길이가 아니라 **세션의 첫 요청인가** 다.
  // 뒤이어 오는 말은 요청이 아니라 답이고("ㅇㅇ 해결햇어?" 도 8자라 길이로는 안 걸러진다),
  // 그걸 이름으로 쓰면 세션명 자리가 방금 친 말로 계속 바뀐다 — 그게 이 오류였다.
  // 훅이 대화 도중에 붙은 세션은 첫 요청을 못 봤으므로 이름을 정하지 않고 폴더 이름으로 둔다.
  const firstPrompt = event === 'UserPromptSubmit' && !previous.promptedAt;
  const promptName = firstPrompt && prompt.trim().length >= NAME_MIN ? prompt : '';
  const isClosed = event === 'SessionEnd';

  const transcriptPath = input.transcript_path || input.transcriptPath;
  const sessionTitle = eventSource === 'codex'
    ? codexThreadNameFrom(rawSessionId)
    : sessionTitleFrom(transcriptPath);
  // 새 명령을 받은 순간에는 아직 할 말이 없다. 비워 두면 펫이 "생각중" 을 띄운다.
  const liveMessage = event === 'UserPromptSubmit' ? '' : lastAssistantTextFrom(transcriptPath);

  const record = {
    sessionId,
    rawSessionId,
    source: eventSource,
    state,
    // 살아 있는 세션에 프로세스가 다시 붙은 것뿐이면 시각도 그대로 둔다.
    // 시각을 밀면 이미 읽은 완료 알림이 안 읽음으로 되살아난다(읽음 판정이 이 시각을 본다).
    event: liveRestart ? (previous.event || event) : event,
    updatedAt: liveRestart ? (previous.updatedAt || now.toISOString()) : now.toISOString(),
    updatedAtMs: liveRestart ? (previous.updatedAtMs || nowMs) : nowMs,
    cwd,
    projectName: basename(cwd),
    // 폴더 이름은 여기 넣지 않는다. 넣으면 그것이 굳어서 나중에 오는 진짜 프롬프트를 막는다.
    // 비워 두면 앱이 폴더 이름으로 내려간다.
    displayTitle: previous.displayTitle || promptName || taskSubject || '',
    sessionTitle: sessionTitle || previous.sessionTitle || '',
    // 앱이 이 파일을 직접 지켜본다. 훅은 도구를 부를 때만 도니, 도구 없이 긴 글을 쓰면
    // 말풍선이 턴 끝까지 안 바뀌었다. 경로를 넘겨 주면 앱이 0.25초마다 새 문장을 집는다.
    transcriptPath: transcriptPath || previous.transcriptPath || '',
    toolName: text(input.tool_name, 80),
    notificationType: text(input.notification_type, 80),
    error,
    lastAssistantMessage: event === 'UserPromptSubmit'
      ? ''
      : (liveMessage || lastAssistantMessage || previous.lastAssistantMessage || ''),
    activeTaskSubject: taskSubject || previous.activeTaskSubject || '',
    backgroundTaskCount,
    attention: liveRestart ? previous.attention === true : attentionFor(state, event),
    closed: isClosed,
    client: eventSource === 'codex' ? 'codex' : (detectClient() || previous.client || ''),
    entrypoint: text(process.env.CLAUDE_CODE_ENTRYPOINT, 40) || previous.entrypoint || '',
    // 사람이 이 세션에 말을 건 적이 있나. 유령 세션을 가려내는 유일한 표식이다.
    promptedAt: event === 'UserPromptSubmit' ? now.toISOString() : (previous.promptedAt || ''),
    startedAt: previous.startedAt || now.toISOString()
  };

  if (event === 'TaskCompleted') record.activeTaskSubject = '';
  if (isClosed) record.closedAt = now.toISOString();
  registry.sessions[sessionId] = record;
  // 프롬프트 한 번 없이 끝난 세션은 껍데기다. 닫힌 기록으로 남기지 말고 지운다.
  if (isGhost(record)) delete registry.sessions[sessionId];

  // 열린 세션은 이레, 닫힌 세션은 하루만 들고 있는다. 앱이 이 파일을 0.25초마다 읽는다.
  const cutoff = nowMs - 7 * 24 * 60 * 60 * 1000;
  const closedCutoff = nowMs - 24 * 60 * 60 * 1000;
  for (const [id, candidate] of Object.entries(registry.sessions)) {
    if (isGhost(candidate)) { delete registry.sessions[id]; continue; }
    const seenAt = candidate.updatedAtMs || 0;
    const limit = candidate.closed ? closedCutoff : cutoff;
    if (seenAt < limit) delete registry.sessions[id];
  }
  registry.updatedAt = now.toISOString();
  writeJSONAtomic(registryPath, registry);
  writeJSONAtomic(legacyStatePath, record);
}

process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => chunks.push(chunk));
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(chunks.join('') || '{}'); } catch {}
  try { withRegistryLock(() => updateRegistry(input, process.argv[2])); } catch {}
});

process.stdin.resume();
