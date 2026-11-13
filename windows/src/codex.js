// Codex 롤아웃(~/.codex/sessions/**/rollout-*.jsonl)과 제목 색인(~/.codex/session_index.jsonl)을 읽는다.
//
// 맥 앱 macos/Sources/Sessions.swift 의 codexTranscriptStatus · reconcileCodexTask · CodexRolloutDiscovery ·
// CodexThreadTitleReader · isCodexSubagentTranscript 를 옮긴 것이다. 값과 순서를 바꿀 때는 Swift 쪽도 같이 고친다.
//
// 있는 이유 — 훅은 즉시성, 롤아웃은 완료 사실, 색인은 제목을 맡는다. 훅을 승인하지 않은 Codex 나
// 훅이 꺼진 Codex(Orca 채팅)도 롤아웃으로 task 를 찾고, Stop 훅을 놓친 완료도 롤아웃에서 바로잡는다.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const SPAN = 512 * 1024;
const RECENT_WINDOW_MS = 24 * 60 * 60 * 1000;
const INPUT_TOOLS = new Set(['request_user_input_async', 'request_user_input']);

function codexHomeDir(home = process.env.RETTO_HOME || os.homedir()) {
  return path.join(home, '.codex');
}

function maxOf(...values) {
  let best = 0;
  for (const value of values) if (typeof value === 'number' && value > best) best = value;
  return best;
}

function mergeMax(left = {}, right = {}) {
  const result = { ...left };
  for (const [key, value] of Object.entries(right)) result[key] = Math.max(result[key] ?? 0, value);
  return result;
}

/// 롤아웃 기록에서 완료·요청·질문·중단 시각을 모은다. 질문 본문은 남기지 않고 ID 와 시각만 남긴다.
function transcriptStatus(text) {
  const status = {
    completedAtMs: undefined,
    latestPromptAtMs: undefined,
    inputRequests: {},
    inputReplies: {},
    inputRequestTurns: {},
    synchronousRequests: {},
    toolOutputs: {},
    abortedTurns: {},
    latestAbortAtMs: undefined,
    composerTurns: {}
  };
  let activeTurn;
  for (const line of String(text).split('\n')) {
    if (!line) continue;
    let record;
    try { record = JSON.parse(line); } catch { continue; }
    const payload = record && record.payload;
    if (!payload || typeof payload !== 'object' || typeof record.timestamp !== 'string') continue;
    const at = Date.parse(record.timestamp);
    if (!Number.isFinite(at)) continue;
    if (record.type === 'event_msg') {
      if (payload.type === 'task_started') {
        const attribution = payload.turn_attribution || {};
        activeTurn = attribution.turn_id || payload.turn_id;
        if (attribution.turn_trigger === 'composer' && activeTurn) {
          status.composerTurns[activeTurn] = Math.max(status.composerTurns[activeTurn] ?? 0, at);
        }
      }
      if (payload.type === 'turn_aborted') {
        status.latestAbortAtMs = Math.max(status.latestAbortAtMs ?? 0, at);
        const turn = payload.turn_id || activeTurn;
        if (turn) status.abortedTurns[turn] = at;
      }
      if (payload.type === 'task_complete') status.completedAtMs = Math.max(status.completedAtMs ?? 0, at);
    }
    if (record.type !== 'response_item') continue;
    if ((payload.type === 'function_call_output' || payload.type === 'custom_tool_call_output') && payload.call_id) {
      status.toolOutputs[payload.call_id] = at;
    }
    if (payload.type === 'function_call' && payload.call_id && typeof payload.arguments === 'string') {
      const name = String(payload.name || '').split('.').pop();
      if (INPUT_TOOLS.has(name)) {
        let questions;
        try { questions = JSON.parse(payload.arguments).questions; } catch {}
        if (Array.isArray(questions)) {
          const turn = (payload.internal_chat_message_metadata_passthrough || {}).turn_id
            || (record.metadata || {}).turn_id || activeTurn;
          questions.forEach((_, index) => {
            const id = `${payload.call_id}:${index}`;
            status.inputRequests[id] = at;
            if (turn) status.inputRequestTurns[id] = turn;
          });
          if (name === 'request_user_input') status.synchronousRequests[payload.call_id] = at;
        }
      }
    }
    if (payload.type === 'message' && payload.role === 'user') {
      status.latestPromptAtMs = Math.max(status.latestPromptAtMs ?? 0, at);
      for (const part of Array.isArray(payload.content) ? payload.content : []) {
        const body = typeof part?.text === 'string' ? part.text : '';
        const match = /<send_user_message_question_reply>([\s\S]*?)<\/send_user_message_question_reply>/.exec(body);
        if (!match) continue;
        let answers;
        try { answers = JSON.parse(match[1]); } catch { continue; }
        for (const answer of Array.isArray(answers) ? answers : []) {
          let id;
          try { id = JSON.parse(answer.questionItemId); } catch { continue; }
          if (!Array.isArray(id) || id.length !== 3 || typeof id[1] !== 'string' || !Number.isInteger(id[2])) continue;
          if (!INPUT_TOOLS.has(String(id[0]).split('.').pop())) continue;
          status.inputReplies[`${id[1]}:${id[2]}`] = at;
        }
      }
    }
  }
  return status;
}

function mergeStatus(older, newer) {
  return {
    completedAtMs: maxOf(older.completedAtMs, newer.completedAtMs) || undefined,
    latestPromptAtMs: maxOf(older.latestPromptAtMs, newer.latestPromptAtMs) || undefined,
    inputRequests: mergeMax(older.inputRequests, newer.inputRequests),
    inputReplies: mergeMax(older.inputReplies, newer.inputReplies),
    inputRequestTurns: { ...older.inputRequestTurns, ...newer.inputRequestTurns },
    synchronousRequests: mergeMax(older.synchronousRequests, newer.synchronousRequests),
    toolOutputs: mergeMax(older.toolOutputs, newer.toolOutputs),
    abortedTurns: mergeMax(older.abortedTurns, newer.abortedTurns),
    latestAbortAtMs: maxOf(older.latestAbortAtMs, newer.latestAbortAtMs) || undefined,
    composerTurns: mergeMax(older.composerTurns, newer.composerTurns)
  };
}

function latestComposerStartAtMs(status) {
  return maxOf(...Object.values(status.composerTurns || {})) || undefined;
}

/// 아직 답하지 않은 질문의 가장 늦은 시각. 없으면 undefined.
function pendingInputAtMs(status) {
  let latest = 0;
  for (const [id, requestedAt] of Object.entries(status.inputRequests || {})) {
    if ((status.inputReplies?.[id] ?? 0) >= requestedAt) continue;
    const turn = status.inputRequestTurns?.[id];
    // 새 사용자 요청은 이전 턴의 질문을 대체한다. 같은 턴의 답변·도구 실행이나 자동 재개는 해제하지 않는다.
    if (Object.entries(status.composerTurns || {}).some(([other, startedAt]) => other !== turn && startedAt > requestedAt)) continue;
    const callId = id.split(':').slice(0, -1).join(':');
    if (status.synchronousRequests?.[callId] != null && (status.toolOutputs?.[callId] ?? 0) >= requestedAt) continue;
    if (turn) {
      if ((status.abortedTurns?.[turn] ?? 0) >= requestedAt) continue;
    } else if ((status.latestAbortAtMs ?? 0) >= requestedAt) {
      continue;
    }
    latest = Math.max(latest, requestedAt);
  }
  return latest || undefined;
}

function latestInputReplyAtMs(status) {
  const syncOutputs = Object.entries(status.toolOutputs || {})
    .filter(([id]) => status.synchronousRequests?.[id] != null).map(([, at]) => at);
  return maxOf(...Object.values(status.inputReplies || {}), ...syncOutputs) || undefined;
}

function isCompletedAfterLatestPrompt(status) {
  if (pendingInputAtMs(status) != null || status.completedAtMs == null) return false;
  return status.completedAtMs > maxOf(status.latestPromptAtMs, status.latestAbortAtMs, latestComposerStartAtMs(status));
}

/// 훅이 적은 Codex 상태를 롤아웃 사실로 바로잡는다(Sessions.swift reconcileCodexTask).
function reconcileTask(session, indexTitle, status) {
  const title = indexTitle || session.sessionTitle;
  const done = isCompletedAfterLatestPrompt(status);
  const result = (state, observedAtMs, needsAttention, stateSource) =>
    ({ ...session, sessionTitle: title, state, updatedAtMs: observedAtMs, needsAttention, stateSource });
  const pending = pendingInputAtMs(status);
  if (pending != null) return result('waiting', pending, true, 'rollout');
  const abortedAt = status.latestAbortAtMs;
  if (abortedAt != null && abortedAt >= (session.updatedAtMs ?? 0) && abortedAt >= (status.latestPromptAtMs ?? 0)
      && abortedAt >= (latestComposerStartAtMs(status) ?? 0) && abortedAt >= (status.completedAtMs ?? 0)) {
    return result('idle', abortedAt, false, 'rollout');
  }
  const startedAt = latestComposerStartAtMs(status);
  if (session.state === 'waiting' && startedAt != null && startedAt > (session.updatedAtMs ?? 0)) {
    return result(done ? 'waving' : 'running', Math.max(startedAt, status.completedAtMs ?? 0), done, 'rollout');
  }
  // 비동기 질문은 답변 뒤에도 훅의 waiting 값이 남을 수 있다.
  const answeredAt = latestInputReplyAtMs(status);
  if (session.state === 'waiting' && answeredAt != null && answeredAt >= (session.updatedAtMs ?? 0)) {
    return result(done ? 'waving' : 'running', Math.max(answeredAt, status.completedAtMs ?? 0), done, 'rollout');
  }
  // 질문 대기는 위에서 유지한다. 권한 훅 이후 턴이 끝났다면 권한 대기도 끝난 상태다.
  const completedAttention = (session.state === 'waiting' || session.state === 'failed')
    && (status.completedAtMs ?? 0) >= (session.updatedAtMs ?? 0);
  if ((session.state === 'running' || session.state === 'review' || completedAttention) && done) {
    return result('waving', status.completedAtMs, true, 'rollout');
  }
  return { ...session, sessionTitle: title, stateSource: session.stateSource || 'hook' };
}

/// 파일 끝을 읽을 때 앞쪽이 잘린 첫 줄은 버린다. JSON 이 반쯤 잘려 다른 기록으로 읽히지 않게 한다.
function readTail(filePath, size) {
  const fd = fs.openSync(filePath, 'r');
  try {
    const start = size > SPAN ? size - SPAN : 0;
    const buffer = Buffer.alloc(size - start);
    fs.readSync(fd, buffer, 0, buffer.length, start);
    let text = buffer.toString('utf8');
    if (start > 0) text = text.slice(text.indexOf('\n') + 1);
    return text;
  } finally {
    fs.closeSync(fd);
  }
}

/// 첫 줄(session_meta). 기본 지시문이 길어 16KB 를 넘으므로 512KB 까지 읽는다.
function readSessionMeta(filePath) {
  let fd;
  try {
    fd = fs.openSync(filePath, 'r');
    const buffer = Buffer.alloc(SPAN);
    const read = fs.readSync(fd, buffer, 0, SPAN, 0);
    const text = buffer.subarray(0, read).toString('utf8');
    const record = JSON.parse(text.split('\n', 1)[0]);
    return record && record.type === 'session_meta' && record.payload ? record.payload : (record?.payload || null);
  } catch {
    return null;
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

const subagentCache = new Map();
/// 이전 worker 파일명과 session_meta 의 source 를 함께 본다(Sessions.swift isCodexSubagentTranscript).
function isSubagentTranscript(filePath) {
  if (!filePath) return false;
  const name = path.basename(filePath).replace(/\.[^.]+$/, '');
  if (/_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(name)) return true;
  let stat;
  try { stat = fs.statSync(filePath); } catch { return false; }
  const key = `${filePath}:${stat.ino}:${stat.size}:${stat.mtimeMs}`;
  if (subagentCache.has(key)) return subagentCache.get(key);
  const meta = readSessionMeta(filePath);
  const source = meta && meta.source;
  const result = source === 'subagent' || Boolean(source && typeof source === 'object' && source.subagent != null);
  if (subagentCache.size > 256) subagentCache.clear();
  subagentCache.set(key, result);
  return result;
}

/// session_index.jsonl → { 스레드 ID: 제목 }. 제목은 80자까지.
function threadTitles(text) {
  const titles = {};
  for (const line of String(text).split('\n')) {
    if (!line) continue;
    let record;
    try { record = JSON.parse(line); } catch { continue; }
    if (record && typeof record.id === 'string' && typeof record.thread_name === 'string' && record.thread_name) {
      titles[record.id] = [...record.thread_name].slice(0, 80).join('');
    }
  }
  return titles;
}

/// 색인 제목이 먼저고, 비었을 때만 다른 출처(Orca 채팅 제목)를 쓴다(codexDiscoveryTitles).
function discoveryTitles(index, extra) {
  const result = { ...extra };
  for (const [id, title] of Object.entries(index)) if (title) result[id] = title;
  return result;
}

class TitleReader {
  constructor(indexPath) { this.indexPath = indexPath; this.stamp = ''; this.titles = {}; }
  all() {
    let stat;
    try { stat = fs.statSync(this.indexPath); } catch { return this.titles; }
    const stamp = `${stat.mtimeMs}:${stat.size}`;
    if (stamp === this.stamp) return this.titles;
    try { this.titles = threadTitles(fs.readFileSync(this.indexPath, 'utf8')); this.stamp = stamp; } catch {}
    return this.titles;
  }
}

/// 롤아웃 파일마다 끝 512KB 를 읽어 상태를 만든다. 크기·수정 시각이 같으면 다시 읽지 않고,
/// 파일이 자라면 이전 상태와 합친다 — 끝 512KB 밖으로 밀려난 완료를 잃지 않으려고.
class TranscriptStatusReader {
  constructor() { this.cache = new Map(); }
  status(filePath) {
    const empty = transcriptStatus('');
    if (!filePath) return empty;
    let stat;
    try { stat = fs.statSync(filePath); } catch { return this.cache.get(filePath)?.status || empty; }
    const cached = this.cache.get(filePath);
    if (cached && cached.size === stat.size && cached.mtimeMs === stat.mtimeMs) return cached.status;
    let tail;
    try { tail = readTail(filePath, stat.size); } catch { return cached?.status || empty; }
    const fresh = transcriptStatus(tail);
    const status = cached && stat.size >= cached.size ? mergeStatus(cached.status, fresh) : fresh;
    this.cache.set(filePath, { size: stat.size, mtimeMs: stat.mtimeMs, status });
    return status;
  }
  retain(paths) {
    for (const key of this.cache.keys()) if (!paths.has(key)) this.cache.delete(key);
  }
}

function listRollouts(dir) {
  const result = [];
  const walk = (current, depth) => {
    let entries;
    try { entries = fs.readdirSync(current, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory() && depth < 4) walk(full, depth + 1);
      else if (entry.isFile() && entry.name.endsWith('.jsonl')) result.push(full);
    }
  };
  walk(dir, 0);
  return result;
}

/// 최근 하루치 롤아웃에서 제목 있는 task 를 찾는다(CodexRolloutDiscovery).
class RolloutDiscovery {
  constructor(home = codexHomeDir()) {
    this.sessionsDir = path.join(home, 'sessions');
    this.titles = new TitleReader(path.join(home, 'session_index.jsonl'));
    this.statuses = new TranscriptStatusReader();
    this.meta = new Map();
    this.diagnostic = '';
  }

  titleFor(threadId) { return this.titles.all()[threadId]; }

  recentTasks({ nowMs = Date.now(), extraTitles = {} } = {}) {
    const titles = discoveryTitles(this.titles.all(), extraTitles);
    const tasks = new Map();
    const visited = new Set();
    let files;
    try { files = listRollouts(this.sessionsDir); } catch { files = []; }
    this.diagnostic = `${this.sessionsDir}: ${files.length} files`;
    for (const file of files) {
      let stat;
      try { stat = fs.lstatSync(file); } catch { continue; }
      if (nowMs - stat.mtimeMs > RECENT_WINDOW_MS || isSubagentTranscript(file)) continue;
      visited.add(file);
      let meta = this.meta.get(file);
      if (!meta) {
        const payload = readSessionMeta(file);
        meta = { threadId: payload?.id || payload?.session_id || null, cwd: payload?.cwd, originator: payload?.originator };
        this.meta.set(file, meta);
      }
      const title = meta.threadId && titles[meta.threadId];
      // 제목이 없는 task 는 내부 세션이라 보이지 않는다. 뒷부분도 읽지 않는다.
      if (!title) continue;
      const status = this.statuses.status(file);
      const done = isCompletedAfterLatestPrompt(status);
      const updatedAtMs = Math.max(status.completedAtMs ?? 0, status.latestPromptAtMs ?? 0, stat.mtimeMs);
      const id = `codex:${meta.threadId}`;
      const task = {
        id,
        sessionId: id,
        rawSessionId: meta.threadId,
        source: 'codex',
        client: 'codex',
        cwd: meta.cwd,
        sessionTitle: title,
        transcriptPath: file,
        event: done ? 'task_complete' : 'rollout',
        state: done ? 'waving' : 'running',
        updatedAtMs,
        needsAttention: done,
        isClosed: false,
        stateSource: 'rollout',
        originator: meta.originator
      };
      const old = tasks.get(id);
      if (!old || (old.updatedAtMs ?? 0) < updatedAtMs) tasks.set(id, task);
    }
    for (const key of this.meta.keys()) if (!visited.has(key)) this.meta.delete(key);
    return [...tasks.values()].sort((a, b) => (b.updatedAtMs ?? 0) - (a.updatedAtMs ?? 0));
  }

  originator(filePath) {
    if (!filePath) return undefined;
    const known = this.meta.get(filePath);
    if (known) return known.originator;
    return readSessionMeta(filePath)?.originator;
  }
}

module.exports = {
  RolloutDiscovery,
  TranscriptStatusReader,
  codexHomeDir,
  discoveryTitles,
  isCompletedAfterLatestPrompt,
  isSubagentTranscript,
  latestInputReplyAtMs,
  mergeStatus,
  pendingInputAtMs,
  readSessionMeta,
  reconcileTask,
  threadTitles,
  transcriptStatus
};
