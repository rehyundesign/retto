// Codex 롤아웃 · Orca 판정이 맥 앱(Sessions.swift · OrcaSessions.swift)과 같은지 본다.
// 맥 앱 자체 검사(SelfTest.swift 「orcaChatStatusOK」, CodexInputSelfTest.swift)와 같은 사례를 쓴다.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const codex = require('../src/codex');
const orca = require('../src/orca');
const { assemble } = require('../src/status');

const line = (type, payload, timestamp) => JSON.stringify({ timestamp: new Date(timestamp).toISOString(), type, payload });
const started = (at, turn = 't1') => line('event_msg', { type: 'task_started', turn_id: turn, turn_attribution: { turn_id: turn, turn_trigger: 'composer' } }, at);
const prompt = (at) => line('response_item', { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'hi' }] }, at);
const complete = (at) => line('event_msg', { type: 'task_complete' }, at);
const question = (at, id = 'q1') => line('response_item', { type: 'function_call', name: 'request_user_input_async', call_id: id, arguments: JSON.stringify({ questions: [{ q: '?' }] }) }, at);
const answer = (at, id = 'q1') => line('response_item', { type: 'message', role: 'user', content: [{ type: 'input_text',
  text: `<send_user_message_question_reply>${JSON.stringify([{ questionItemId: JSON.stringify(['request_user_input_async', id, 0]) }])}</send_user_message_question_reply>` }] }, at);
const aborted = (at, turn = 't1') => line('event_msg', { type: 'turn_aborted', turn_id: turn }, at);

test('완료 · 질문 · 답 · 중단을 롤아웃에서 읽는다', () => {
  const done = codex.transcriptStatus([started(1000), prompt(1000), complete(2000)].join('\n'));
  assert.equal(done.completedAtMs, 2000);
  assert.equal(codex.isCompletedAfterLatestPrompt(done), true);
  const again = codex.transcriptStatus([started(1000), prompt(1000), complete(2000), started(3000, 't2'), prompt(3000)].join('\n'));
  assert.equal(codex.isCompletedAfterLatestPrompt(again), false, '완료 뒤 새 요청은 완료가 아니다');
  const asking = codex.transcriptStatus([started(1000), question(1500)].join('\n'));
  assert.equal(codex.pendingInputAtMs(asking), 1500);
  assert.equal(codex.isCompletedAfterLatestPrompt(asking), false);
  const answered = codex.transcriptStatus([started(1000), question(1500), answer(1700)].join('\n'));
  assert.equal(codex.pendingInputAtMs(answered), undefined);
  const cancelled = codex.transcriptStatus([started(1000), question(1500), aborted(1600)].join('\n'));
  assert.equal(codex.pendingInputAtMs(cancelled), undefined, '중단된 턴의 질문은 풀린다');
  const superseded = codex.transcriptStatus([started(1000), question(1500), started(1800, 't2')].join('\n'));
  assert.equal(codex.pendingInputAtMs(superseded), undefined, '새 턴이 이전 질문을 대체한다');
  const merged = codex.mergeStatus(asking, codex.transcriptStatus(answer(1700)));
  assert.equal(codex.pendingInputAtMs(merged), undefined, '나눠 읽은 답도 질문을 푼다');
});

test('훅 상태를 롤아웃 사실로 바로잡는다', () => {
  const status = codex.transcriptStatus([started(1000), prompt(1000), complete(2000)].join('\n'));
  const fixed = codex.reconcileTask({ state: 'running', updatedAtMs: 1000, sessionTitle: '옛 제목' }, '새 제목', status);
  assert.equal(fixed.state, 'waving');
  assert.equal(fixed.updatedAtMs, 2000);
  assert.equal(fixed.sessionTitle, '새 제목');
  const kept = codex.reconcileTask({ state: 'running', updatedAtMs: 3000 }, null, codex.transcriptStatus([started(2500), prompt(2500)].join('\n')));
  assert.equal(kept.state, 'running');
});

test('제목 색인과 Orca 제목을 합친다', () => {
  assert.deepEqual(codex.threadTitles('{"id":"a","thread_name":"하나"}\n{"id":"b","thread_name":""}\n{'), { a: '하나' });
  assert.deepEqual(codex.discoveryTitles({ a: '색인', b: '' }, { a: 'Orca', b: 'Orca 비', c: 'Orca 만' }), { a: '색인', b: 'Orca 비', c: 'Orca 만' });
});

test('롤아웃에서 최근 task 를 찾는다 — 제목 없는 것과 worker 는 뺀다', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'retto-codex-'));
  const day = path.join(home, 'sessions', '2026', '11', '13');
  fs.mkdirSync(day, { recursive: true });
  const now = Date.now();
  const meta = (id, extra = {}) => JSON.stringify({ type: 'session_meta', payload: { id, cwd: 'C:/work/app', ...extra } });
  fs.writeFileSync(path.join(day, 'rollout-a.jsonl'), [meta('thread-a'), started(now - 5000), prompt(now - 5000), complete(now - 1000)].join('\n') + '\n');
  fs.writeFileSync(path.join(day, 'rollout-b.jsonl'), [meta('thread-b', { originator: 'orca_desktop' }), started(now - 5000), prompt(now - 5000)].join('\n') + '\n');
  fs.writeFileSync(path.join(day, 'rollout-c.jsonl'), [meta('thread-c', { source: 'subagent' }), started(now - 5000)].join('\n') + '\n');
  fs.writeFileSync(path.join(day, 'rollout-d.jsonl'), [meta('thread-d'), started(now - 5000)].join('\n') + '\n');
  fs.writeFileSync(path.join(home, 'session_index.jsonl'), ['a', 'c'].map((x) => JSON.stringify({ id: `thread-${x}`, thread_name: `제목 ${x}` })).join('\n'));
  const discovery = new codex.RolloutDiscovery(home);
  const tasks = discovery.recentTasks({ nowMs: now, extraTitles: { 'thread-b': 'Orca 제목' } });
  assert.deepEqual(tasks.map((t) => t.id).sort(), ['codex:thread-a', 'codex:thread-b']);
  const a = tasks.find((t) => t.id === 'codex:thread-a');
  assert.equal(a.state, 'waving');
  assert.equal(a.sessionTitle, '제목 a');
  const b = tasks.find((t) => t.id === 'codex:thread-b');
  assert.equal(b.state, 'running');
  assert.equal(b.originator, 'orca_desktop');
  fs.rmSync(home, { recursive: true, force: true });
});

test('Orca 채팅 상태 — blocked·waiting 은 입력 대기, done+failure 는 실패, 못 잇는 탭은 버린다', () => {
  const chats = [
    { sessionId: 'codex_a', status: { state: 'blocked', mainAgent: { state: 'blocked', stateStartedAt: 5000 } } },
    { sessionId: 'codex_b', status: { state: 'working', updatedAt: 4000 } },
    { sessionId: 'codex_c', status: { state: 'blocked', updatedAt: 4000 } },
    { sessionId: 'codex_d', status: { state: 'waiting', updatedAt: 4000 } },
    { sessionId: 'codex_e', status: { state: 'done', updatedAt: 4000 } },
    { sessionId: 'codex_f', status: { state: 'done', mainAgent: { state: 'done', outcome: 'failure', stateStartedAt: 5500 } } },
    { sessionId: 'codex_g', status: { state: 'blocked', updatedAt: 4000 } },
    { sessionId: 'bad id', status: { state: 'blocked', updatedAt: 4000 } }
  ];
  const before = { codex_a: 'thread-a', codex_b: 'thread-b', codex_d: 'thread-d', codex_e: 'thread-d', codex_f: 'thread-f', codex_g: 'thread-g', 'bad id': 'thread-x' };
  const after = { ...before, codex_g: 'thread-g2' };
  const statuses = orca.chatStatuses(chats, before, after);
  assert.deepEqual(Object.keys(statuses).sort(), ['thread-a', 'thread-b', 'thread-f']);
  assert.deepEqual(statuses['thread-a'], { orcaSessionId: 'codex_a', threadId: 'thread-a', needsInput: true, sinceMs: 5000, failed: false, cancelled: false });
  assert.equal(statuses['thread-f'].failed, true);

  const running = { state: 'running', updatedAtMs: 3000, source: 'codex', orcaHosted: true, rawSessionId: 'thread-a' };
  const waiting = orca.applyChatStatus(statuses['thread-a'], running);
  assert.equal(waiting.state, 'waiting');
  assert.equal(waiting.orcaSessionId, 'codex_a');
  assert.equal(waiting.updatedAtMs, 5000);
  const finished = { ...running, state: 'waving', updatedAtMs: 6000 };
  assert.equal(orca.applyChatStatus(statuses['thread-a'], finished).state, 'waiting', '내 답을 기다리며 끝난 턴도 blocked 다');
  assert.equal(orca.applyChatStatus(statuses['thread-f'], finished).state, 'failed');
  assert.equal(orca.applyChatStatus(statuses['thread-f'], { ...running, updatedAtMs: 7000 }, 7000).state, 'running', '실패 뒤 새 턴');
  assert.equal(orca.applyChatStatus(statuses['thread-f'], { ...running, updatedAtMs: 7000 }, 5000).state, 'failed', '파일 시각이 실패 뒤여도 새 요청이 없으면 실패');
  const cancelled = { orcaSessionId: 'codex_c', threadId: 'thread-c', needsInput: false, sinceMs: 6500, failed: false, cancelled: true };
  assert.equal(orca.applyChatStatus(cancelled, { ...running, updatedAtMs: 7000 }, 5000).state, 'idle', '멈춘 턴은 쉬는 중');
  assert.equal(orca.applyChatStatus(cancelled, { ...running, updatedAtMs: 7000 }, 7000).state, 'running');
  assert.equal(orca.applyChatStatus(cancelled, finished).state, 'waving');
  assert.equal(orca.applyChatStatus(statuses['thread-b'], running).state, 'running');
  assert.equal(orca.applyChatStatus(undefined, running), running);
});

test('Orca 에 물어볼 채팅 — 원래 상태와 마지막 활동으로 고른다', () => {
  const min = 60 * 1000;
  assert.equal(orca.needsWatching('running', 1, 1 + 30 * min), true);
  assert.equal(orca.needsWatching('running', 1, 1 + 180 * min), false);
  assert.equal(orca.needsWatching('waving', 1, 1 + 5 * min), true);
  assert.equal(orca.needsWatching('waving', 1, 1 + 20 * min), false);
  assert.equal(orca.needsWatching('idle', 1, 2), false);
  assert.equal(orca.needsWatching('running', 0, 2), false);
});

test('Orca 세션 기록에서 제목과 스레드를 읽는다 — 한 스레드를 두 채팅이 가리키면 탭 ID 를 비운다', () => {
  const record = JSON.stringify({ conversationName: ' Orca 제목 ', providerHandleChain: [
    { handle: { provider: 'codex', threadId: 'thread-old' } }, { handle: { provider: 'codex', threadId: 'thread-t' } }] });
  assert.deepEqual(orca.codexThreadFromRecord(record, 'codex_t'), { threadId: 'thread-t', thread: { orcaSessionId: 'codex_t', title: 'Orca 제목' } });
  assert.equal(orca.codexThreadFromRecord('{"providerHandleChain":[]}', 'x'), null);
  assert.equal(orca.codexThreadFromRecord('{', 'x'), null);

  const { DatabaseSync } = require('node:sqlite');
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'retto-orca-')), 'journal.db');
  const db = new DatabaseSync(file);
  const dup = JSON.stringify({ conversationName: '둘', providerHandleChain: [{ handle: { provider: 'codex', threadId: 'thread-dup' } }] });
  db.exec('CREATE TABLE agent_session_records (session_id TEXT PRIMARY KEY, record_json TEXT NOT NULL)');
  const insert = db.prepare('INSERT INTO agent_session_records VALUES (?, ?)');
  for (const [id, json] of [['codex_t', record], ['codex_d1', dup], ['codex_d2', dup], ['claude_x', record], ['codex_bad', '{']]) insert.run(id, json);
  db.close();
  assert.deepEqual(orca.readThreads(file), {
    'thread-t': { orcaSessionId: 'codex_t', title: 'Orca 제목' },
    'thread-dup': { orcaSessionId: '', title: '둘' }
  });
  fs.rmSync(path.dirname(file), { recursive: true, force: true });
});

test('합치기 — 제목 없는 Orca 롤아웃에 Orca 제목·탭 ID 를 붙이고, Orca 대기를 겹친다', () => {
  const task = { id: 'codex:thread-t', rawSessionId: 'thread-t', source: 'codex', client: 'codex', sessionTitle: 'Orca 제목',
    state: 'running', updatedAtMs: 3000, originator: 'orca_desktop', stateSource: 'rollout' };
  const hookCodex = { id: 'codex:thread-h', rawSessionId: 'thread-h', source: 'codex', sessionTitle: '훅 task', state: 'running', updatedAtMs: 3000 };
  const untitled = { id: 'codex:thread-u', rawSessionId: 'thread-u', source: 'codex', state: 'running', updatedAtMs: 3000 };
  const claude = { id: 'c1', source: 'claude', client: 'orca', orcaSessionId: 'claude_1', state: 'waving', updatedAtMs: 1 };
  const out = assemble({
    hookSessions: [hookCodex, untitled, claude],
    rollouts: [task, { ...hookCodex, sessionTitle: '롤아웃 쪽' }],
    threads: { 'thread-t': { orcaSessionId: 'codex_t', title: 'Orca 제목' } },
    originator: () => undefined,
    indexTitle: () => undefined,
    transcript: () => codex.transcriptStatus(''),
    chatStatus: (id) => (id === 'thread-t' ? { orcaSessionId: 'codex_t', needsInput: true, sinceMs: 5000, failed: false } : undefined)
  });
  assert.deepEqual(out.map((s) => s.id).sort(), ['c1', 'codex:thread-h', 'codex:thread-t']);
  const orcaTask = out.find((s) => s.id === 'codex:thread-t');
  assert.equal(orcaTask.orcaHosted, true);
  assert.equal(orcaTask.orcaSessionId, 'codex_t');
  assert.equal(orcaTask.state, 'waiting');
  assert.equal(out.find((s) => s.id === 'codex:thread-h').sessionTitle, '훅 task', '훅에 있는 task 는 롤아웃으로 덮지 않는다');
  assert.deepEqual(orca.openRequest(orcaTask), { sessionId: 'codex_t', terminalHandle: null, workspacePath: null, agent: 'codex', codexThreadId: 'thread-t' });
  assert.equal(orca.openRequest(hookCodex), null);
});
