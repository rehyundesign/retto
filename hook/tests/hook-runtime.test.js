const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

function invoke(hookPath, payload, fallbackState = 'idle', env = undefined) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [hookPath, fallbackState], {
      stdio: ['pipe', 'ignore', 'pipe'],
      env: { ...process.env, CLAUDE_CODE_ENTRYPOINT: '', CLAUDE_CODE_EXECPATH: '', ...env }
    });
    let stderr = '';
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('exit', (code) => code === 0 ? resolve() : reject(new Error(stderr || `exit ${code}`)));
    child.stdin.end(JSON.stringify(payload));
  });
}

test('keeps concurrent Claude sessions instead of losing the last writer', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'reto-hook-'));
  const hookPath = path.join(directory, 'hook.cjs');
  fs.copyFileSync(path.join(__dirname, '..', 'hook.cjs'), hookPath);
  const count = 16;
  await Promise.all(Array.from({ length: count }, (_, index) => invoke(hookPath, {
    hook_event_name: index % 3 === 0 ? 'PermissionRequest' : 'UserPromptSubmit',
    session_id: `session-${index}`,
    cwd: `/tmp/project-${index}`,
    prompt: `작업 ${index}`
  }, 'running')));

  const registry = JSON.parse(fs.readFileSync(path.join(directory, 'sessions.json'), 'utf8'));
  assert.equal(Object.keys(registry.sessions).length, count);
  assert.equal(registry.sessions['session-0'].state, 'waiting');
  assert.equal(registry.sessions['session-1'].displayTitle, '작업 1');
});

test('maps read tools to review and mutating tools to running', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'reto-hook-state-'));
  const hookPath = path.join(directory, 'hook.cjs');
  fs.copyFileSync(path.join(__dirname, '..', 'hook.cjs'), hookPath);
  await invoke(hookPath, { hook_event_name: 'PreToolUse', session_id: 'read', tool_name: 'Read' });
  await invoke(hookPath, { hook_event_name: 'PreToolUse', session_id: 'write', tool_name: 'Edit' });
  const registry = JSON.parse(fs.readFileSync(path.join(directory, 'sessions.json'), 'utf8'));
  assert.equal(registry.sessions.read.state, 'review');
  assert.equal(registry.sessions.write.state, 'running');
});

/// 오버레이는 이 값으로 클릭했을 때 VS Code 를 띄울지 Claude 앱을 띄울지 정한다.
/// 훅이 환경변수를 잘못 읽으면 클릭이 통째로 엉뚱한 앱으로 간다.
test('records which client each session came from', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'reto-hook-client-'));
  const hookPath = path.join(directory, 'hook.cjs');
  fs.copyFileSync(path.join(__dirname, '..', 'hook.cjs'), hookPath);

  const cases = [
    ['code', { CLAUDE_CODE_ENTRYPOINT: 'claude-vscode' }, 'vscode'],
    // 실측값. 앱 번들 코드만 읽고 sdk-ts 로 짐작했다가 실제 세션을 오분류했다.
    ['desktop', { CLAUDE_CODE_ENTRYPOINT: 'claude-desktop' }, 'claude'],
    ['sdk', { CLAUDE_CODE_ENTRYPOINT: 'sdk-ts' }, 'claude'],
    ['agent', { CLAUDE_CODE_ENTRYPOINT: 'local-agent' }, 'claude'],
    ['terminal', { CLAUDE_CODE_ENTRYPOINT: 'cli' }, 'cli'],
    ['unknown', {}, ''],
    // EXECPATH 는 더 이상 보지 않는다. VS Code 바이너리로 데스크탑 앱이 돌아도 entrypoint 가 답이다.
    ['desktop-via-code-binary', {
      CLAUDE_CODE_ENTRYPOINT: 'claude-desktop',
      CLAUDE_CODE_EXECPATH: '/Users/x/.vscode/extensions/anthropic.claude-code/resources/native-binary/claude'
    }, 'claude']
  ];
  for (const [sessionId, env, expected] of cases) {
    await invoke(hookPath, { hook_event_name: 'UserPromptSubmit', session_id: sessionId }, 'running', env);
    const registry = JSON.parse(fs.readFileSync(path.join(directory, 'sessions.json'), 'utf8'));
    assert.equal(registry.sessions[sessionId].client, expected, sessionId);
  }
});

/// 클라이언트를 못 읽은 훅 한 번이 이미 알아낸 값을 지우면, 그 세션 클릭이 그때부터 엉뚱한 앱으로 간다.
test('keeps a known client when a later hook cannot read the environment', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'reto-hook-client-keep-'));
  const hookPath = path.join(directory, 'hook.cjs');
  fs.copyFileSync(path.join(__dirname, '..', 'hook.cjs'), hookPath);
  await invoke(hookPath, { hook_event_name: 'UserPromptSubmit', session_id: 's' }, 'running', { CLAUDE_CODE_ENTRYPOINT: 'sdk-ts' });
  await invoke(hookPath, { hook_event_name: 'Stop', session_id: 's' }, 'waving', {});
  const registry = JSON.parse(fs.readFileSync(path.join(directory, 'sessions.json'), 'utf8'));
  assert.equal(registry.sessions.s.client, 'claude');
});

const DESKTOP = { CLAUDE_CODE_ENTRYPOINT: 'claude-desktop' };

function freshHook(prefix) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  fs.copyFileSync(path.join(__dirname, '..', 'hook.cjs'), path.join(directory, 'hook.cjs'));
  return directory;
}

function registry(directory) {
  return JSON.parse(fs.readFileSync(path.join(directory, 'sessions.json'), 'utf8')).sessions;
}

/// Claude 데스크탑 앱은 턴마다 프로세스를 새로 띄웠다 내려서 Stop 2초 뒤에 SessionStart 가 또 온다.
/// 그걸 그대로 받으면 jumping(20) 이 running(40)·waving(55) 을 덮어 세션이 목록 바닥으로 내려가고,
/// 레토가 그 세션을 아예 안 쳐다본다. 클로드 앱에서 "생각중" 이 안 뜨던 이유가 이것이다.
test('a restart on a live session does not overwrite what it was doing', async () => {
  const directory = freshHook('reto-hook-restart-');
  const hookPath = path.join(directory, 'hook.cjs');

  await invoke(hookPath, { hook_event_name: 'UserPromptSubmit', session_id: 's', prompt: '해줘' }, 'running', DESKTOP);
  const working = registry(directory).s;
  await invoke(hookPath, { hook_event_name: 'SessionStart', session_id: 's', source: 'resume' }, 'idle', DESKTOP);
  const after = registry(directory).s;

  assert.equal(after.state, 'running');
  // 시각까지 그대로여야 한다. 밀면 이미 읽은 알림이 안 읽음으로 되살아난다.
  assert.equal(after.updatedAtMs, working.updatedAtMs);
});

test('a restart right after Stop keeps the completion notice', async () => {
  const directory = freshHook('reto-hook-restart-done-');
  const hookPath = path.join(directory, 'hook.cjs');

  await invoke(hookPath, { hook_event_name: 'UserPromptSubmit', session_id: 's', prompt: '해줘' }, 'running', DESKTOP);
  await invoke(hookPath, { hook_event_name: 'Stop', session_id: 's' }, 'waving', DESKTOP);
  await invoke(hookPath, { hook_event_name: 'SessionStart', session_id: 's', source: 'resume' }, 'idle', DESKTOP);

  const after = registry(directory).s;
  assert.equal(after.state, 'waving');
  assert.equal(after.attention, true);
});

/// 오래 쉰 세션을 진짜로 되살린 것은 반겨야 한다. 유예를 통째로 무시하면 그게 사라진다.
test('a restart on a long-quiet session still greets', async () => {
  const directory = freshHook('reto-hook-restart-old-');
  const hookPath = path.join(directory, 'hook.cjs');

  await invoke(hookPath, { hook_event_name: 'Stop', session_id: 's' }, 'waving', DESKTOP);
  const registryPath = path.join(directory, 'sessions.json');
  const stored = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
  const longAgo = Date.now() - 3 * 60 * 60 * 1000;
  stored.sessions.s.updatedAtMs = longAgo;
  fs.writeFileSync(registryPath, JSON.stringify(stored));

  await invoke(hookPath, { hook_event_name: 'SessionStart', session_id: 's', source: 'resume' }, 'idle', DESKTOP);
  const after = registry(directory).s;
  assert.equal(after.state, 'jumping');
  assert.ok(after.updatedAtMs > longAgo);
});

/// 클로드 앱은 창을 띄우거나 폴더를 훑을 때마다 프롬프트 한 번 없는 세션을 1초짜리로 만들었다 버린다.
/// 실측에서 한 번에 세 개씩 났다. 껍데기로 남으면 레지스트리가 하루치 쓰레기로 찬다.
test('a session that ended without anyone saying anything leaves no record', async () => {
  const directory = freshHook('reto-hook-ghost-');
  const hookPath = path.join(directory, 'hook.cjs');

  await invoke(hookPath, { hook_event_name: 'SessionStart', session_id: 'ghost', cwd: '/tmp/x' }, 'idle', DESKTOP);
  assert.ok(registry(directory).ghost, '살아 있는 동안에는 있어야 한다');
  await invoke(hookPath, { hook_event_name: 'SessionEnd', session_id: 'ghost', cwd: '/tmp/x' }, 'idle', DESKTOP);
  assert.equal(registry(directory).ghost, undefined);
});

test('a session someone actually used survives its end', async () => {
  const directory = freshHook('reto-hook-real-end-');
  const hookPath = path.join(directory, 'hook.cjs');

  await invoke(hookPath, { hook_event_name: 'UserPromptSubmit', session_id: 'real', prompt: '해줘' }, 'running', DESKTOP);
  await invoke(hookPath, { hook_event_name: 'SessionEnd', session_id: 'real' }, 'idle', DESKTOP);
  const after = registry(directory).real;
  assert.equal(after.closed, true);
  assert.ok(after.promptedAt);
});

/// 이미 쌓인 껍데기도 다음 훅이 돌 때 함께 쓸어낸다.
test('ghosts already in the file get swept on the next write', async () => {
  const directory = freshHook('reto-hook-sweep-');
  const hookPath = path.join(directory, 'hook.cjs');
  fs.writeFileSync(path.join(directory, 'sessions.json'), JSON.stringify({
    version: 1,
    sessions: {
      husk: { sessionId: 'husk', state: 'idle', closed: true, updatedAtMs: Date.now() },
      kept: { sessionId: 'kept', state: 'idle', closed: true, updatedAtMs: Date.now(), sessionTitle: '백오피스' }
    }
  }));

  await invoke(hookPath, { hook_event_name: 'UserPromptSubmit', session_id: 'new', prompt: '해줘' }, 'running', DESKTOP);
  const after = registry(directory);
  assert.equal(after.husk, undefined);
  assert.ok(after.kept);
});
