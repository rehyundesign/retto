// 자체 점검 — `Retto.exe --self-check <결과.json>`. Windows PC 가 없어서, Windows 에서만 다르게 도는 부분을
// GitHub Actions 의 실제 Windows 에서 돌려 보려고 둔다(.github/workflows/windows.yml).
//
// 보는 것: 토큰 암호화(safeStorage · DPAPI), ping 되는 소켓(ws), node:sqlite, Codex 롤아웃 · 트랜스크립트 읽기
// (Windows 경로), Orca 찾기와 런타임 연결, 스킨 파일. 사용자의 실제 파일은 건드리지 않는다 — 임시 폴더만 쓴다.
// 실패한 항목과 이유를 남기고, 꼭 돼야 하는 항목(critical)이 하나라도 틀리면 종료 코드 1.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

async function check(results, name, critical, run) {
  const started = Date.now();
  try {
    const detail = await run();
    results.push({ name, ok: true, critical, ms: Date.now() - started, detail });
  } catch (error) {
    results.push({ name, ok: false, critical, ms: Date.now() - started, error: String(error?.stack || error).slice(0, 2000) });
  }
}

function assert(value, message) { if (!value) throw new Error(message); }

async function runSelfCheck({ safeStorage, skinsDir, orcaRequired = false }) {
  const results = [];
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'retto-self-check-'));
  const slack = require('./slack');
  const codex = require('./codex');
  const orca = require('./orca');
  const { TranscriptReader } = require('./transcript');

  await check(results, 'slack-token-encryption', true, () => {
    assert(safeStorage.isEncryptionAvailable(), 'safeStorage 를 쓸 수 없다');
    const file = path.join(temp, 'slack', 'credentials.bin');
    const store = slack.fileStore({ fs, filePath: file, safeStorage });
    store.write({ userToken: 'xoxp-self-check-1', appToken: 'xapp-self-check-2' });
    const raw = fs.readFileSync(file);
    assert(!raw.toString('latin1').includes('xoxp-self-check'), '파일에 토큰이 평문으로 남았다');
    const back = store.read();
    assert(back.userToken === 'xoxp-self-check-1' && back.appToken === 'xapp-self-check-2', '복호화 값이 다르다');
    store.delete();
    assert(store.read() === null, '지운 뒤에도 읽힌다');
    return { bytes: raw.length };
  });

  await check(results, 'slack-socket-ping', true, async () => {
    const WebSocket = require('ws');
    const server = new WebSocket.WebSocketServer({ port: 0, host: '127.0.0.1' });
    await new Promise((resolve) => server.once('listening', resolve));
    try {
      const client = new WebSocket(`ws://127.0.0.1:${server.address().port}`);
      await new Promise((resolve, reject) => { client.once('open', resolve); client.once('error', reject); });
      const pong = new Promise((resolve) => client.once('pong', resolve));
      client.ping();
      await Promise.race([pong, new Promise((_, reject) => setTimeout(() => reject(new Error('pong 이 오지 않았다')), 3000))]);
      assert(typeof client.addEventListener === 'function', 'addEventListener 가 없다');
      client.terminate();
      return { ping: 'pong' };
    } finally { server.close(); }
  });

  await check(results, 'orca-journal-sqlite', true, () => {
    const { DatabaseSync } = require('node:sqlite');
    const file = path.join(temp, 'journal.db');
    const db = new DatabaseSync(file);
    db.exec('CREATE TABLE agent_session_records (session_id TEXT PRIMARY KEY, record_json TEXT NOT NULL)');
    db.prepare('INSERT INTO agent_session_records VALUES (?, ?)').run('codex_a',
      JSON.stringify({ conversationName: '한글 제목', providerHandleChain: [{ handle: { provider: 'codex', threadId: 'thread-a' } }] }));
    db.close();
    const threads = orca.readThreads(file);
    assert(threads['thread-a']?.title === '한글 제목' && threads['thread-a']?.orcaSessionId === 'codex_a', JSON.stringify(threads));
    return threads;
  });

  await check(results, 'codex-rollouts-windows-paths', true, () => {
    const home = path.join(temp, '홈 폴더', '.codex');
    const day = path.join(home, 'sessions', '2026', '11', '13');
    fs.mkdirSync(day, { recursive: true });
    const now = Date.now();
    const line = (type, payload, at) => JSON.stringify({ timestamp: new Date(at).toISOString(), type, payload });
    fs.writeFileSync(path.join(day, 'rollout-a.jsonl'), [
      JSON.stringify({ type: 'session_meta', payload: { id: 'thread-w', cwd: 'C:\\work\\랜딩', originator: 'orca_desktop' } }),
      line('event_msg', { type: 'task_started', turn_id: 't1' }, now - 5000),
      line('response_item', { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'hi' }] }, now - 5000),
      line('response_item', { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: '고쳤어요 https://example.com/a/b' }] }, now - 2000),
      line('event_msg', { type: 'task_complete' }, now - 1000)
    ].join('\r\n') + '\r\n');
    fs.writeFileSync(path.join(home, 'session_index.jsonl'), JSON.stringify({ id: 'thread-w', thread_name: '윈도우 task' }) + '\r\n');
    const tasks = new codex.RolloutDiscovery(home).recentTasks({ nowMs: now });
    assert(tasks.length === 1 && tasks[0].state === 'waving' && tasks[0].sessionTitle === '윈도우 task', JSON.stringify(tasks));
    assert(tasks[0].cwd === 'C:\\work\\랜딩' && tasks[0].originator === 'orca_desktop', 'session_meta 를 못 읽었다');
    const live = new TranscriptReader().read(tasks[0].transcriptPath);
    assert(live.message.startsWith('고쳤어요'), `트랜스크립트 문장: ${live.message}`);
    return { task: tasks[0].id, transcript: tasks[0].transcriptPath, message: live.message };
  });

  await check(results, 'orca-runtime', orcaRequired, async () => {
    const started = Date.now();
    const running = orca.runningOrcaResources();
    const lookupMs = Date.now() - started;
    const userData = orca.userDataDir();
    const detail = { running, lookupMs, userData, userDataExists: Boolean(userData && fs.existsSync(userData)),
      localAppData: process.env.LOCALAPPDATA || null };
    assert(lookupMs < 6000, `Orca 찾기가 ${lookupMs}ms 걸렸다`);
    if (!running) {
      if (orcaRequired) throw new Error(`떠 있는 Orca 를 찾지 못했다 ${JSON.stringify(detail)}`);
      return { ...detail, note: 'Orca 가 떠 있지 않다 — 아무것도 하지 않는 것이 맞다' };
    }
    const clientPath = orca.runtimeClientPath(running);
    assert(clientPath, `runtime-client.js 가 없다: ${running}`);
    const reader = new orca.ChatStatusReader({ onChange() {} });
    reader.tracked = new Set(['self-check']);
    await reader.poll();
    const { RuntimeClient } = require(clientPath);
    const response = await new RuntimeClient(undefined, undefined, null, null).call('session.tabs.listAll', {});
    assert(response && response.ok !== false, `session.tabs.listAll 실패: ${JSON.stringify(response).slice(0, 300)}`);
    return { ...detail, clientPath, snapshots: (response.result?.snapshots || []).length,
      journal: fs.existsSync(path.join(userData, 'agent-session-journal.db')) };
  });

  await check(results, 'skins', false, () => {
    const manifestPath = path.join(skinsDir, 'manifest.json');
    if (!fs.existsSync(manifestPath)) return { note: '스킨 프레임이 없다(CI 빌드) — 기본 아틀라스로 그린다' };
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const missing = [];
    for (const skin of manifest.skins) {
      for (const clip of Object.values(skin.clips)) if (!fs.existsSync(path.join(skinsDir, skin.id, clip.file))) missing.push(`${skin.id}/${clip.file}`);
    }
    assert(missing.length === 0, `빠진 파일: ${missing.join(', ')}`);
    return { skins: manifest.skins.map((s) => s.id) };
  });

  fs.rmSync(temp, { recursive: true, force: true });
  const ok = results.every((r) => r.ok || !r.critical);
  return { ok, platform: process.platform, arch: process.arch, electron: process.versions.electron, node: process.versions.node, results };
}

module.exports = { runSelfCheck };
