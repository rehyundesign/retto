const test = require('node:test');
const assert = require('node:assert/strict');
const {
  CODEX_EVENT_STATES,
  EVENT_STATES,
  REQUIRED_EVENT_STATES,
  mergeRettoCodexHooks,
  mergeRettoHooks,
  removeRettoCodexHooks,
  removeRettoHooks,
  shimPathFor
} = require('../lib/hook-settings');

const hookPath = '/Users/example/.claude/retto-pet/hook.cjs';
const shimPath = '/Users/example/.claude/retto-pet/hook.sh';

function rettoHandlers(settings, event) {
  return (settings.hooks[event] || [])
    .flatMap((group) => group.hooks || [])
    .filter((handler) => typeof handler.command === 'string' && handler.command.includes(shimPath));
}

test('merges Reto hooks without replacing existing Claude hooks', () => {
  const existing = {
    theme: 'dark',
    hooks: {
      PreToolUse: [{ matcher: 'Bash', hooks: [{ type: 'command', command: 'safe-check' }] }]
    }
  };
  const result = mergeRettoHooks(existing, hookPath);
  assert.equal(result.theme, 'dark');
  assert.equal(result.hooks.PreToolUse[0].hooks[0].command, 'safe-check');
  assert.equal(result.hooks.PreToolUse.length, 2);
  assert.equal(Object.values(result.hooks).flat().length, EVENT_STATES.length + 1);
});

test('install is idempotent', () => {
  const first = mergeRettoHooks({}, hookPath);
  const second = mergeRettoHooks(first, hookPath);
  for (const entry of EVENT_STATES) {
    const expected = EVENT_STATES.filter((candidate) => candidate.event === entry.event).length;
    assert.equal(rettoHandlers(second, entry.event).length, expected, entry.event);
  }
});

test('removes only Reto handlers and keeps neighboring handlers', () => {
  const settings = {
    hooks: {
      Stop: [{ hooks: [
        { type: 'command', command: 'announce' },
        { type: 'command', command: `'${shimPath}' 'waving'` }
      ] }]
    }
  };
  const result = removeRettoHooks(settings, hookPath);
  assert.deepEqual(result.hooks.Stop[0].hooks, [{ type: 'command', command: 'announce' }]);
});

test('upgrading from the old command+args shape leaves no dead entries behind', () => {
  // 0.7.0 까지는 이렇게 등록했다. 갱신할 때 이 항목을 알아보지 못하면
  // 사라진 node 경로를 가리키는 훅이 열일곱 개 그대로 남는다.
  const legacy = {
    hooks: {
      Stop: [{ hooks: [{ type: 'command', command: '/opt/homebrew/bin/node', args: [hookPath, 'waving'] }] }],
      SessionStart: [{ hooks: [{ type: 'command', command: 'node', args: ['/Users/example/.claude/reto-pet/hook.cjs', 'idle'] }] }]
    }
  };
  const result = mergeRettoHooks(legacy, hookPath);
  const survivors = Object.values(result.hooks)
    .flat()
    .flatMap((group) => group.hooks || [])
    .filter((handler) => Array.isArray(handler.args));
  assert.deepEqual(survivors, []);
  assert.equal(rettoHandlers(result, 'Stop').length, 1);
  assert.equal(rettoHandlers(result, 'SessionStart').length, 1);
});

test('does not mutate caller settings', () => {
  const settings = { hooks: { Stop: [{ hooks: [{ type: 'command', command: 'announce' }] }] } };
  const snapshot = JSON.stringify(settings);
  mergeRettoHooks(settings, hookPath);
  assert.equal(JSON.stringify(settings), snapshot);
});

test('registers one shell command line so old Claude Code versions can read it', () => {
  // command 한 줄 문자열은 오래된 규격이다. command + args 로 나눠 적으면
  // 그 모양을 모르는 버전에서 훅이 아무 일도 하지 않는다.
  const result = mergeRettoHooks({}, hookPath);
  const handler = result.hooks.UserPromptSubmit[0].hooks[0];
  assert.equal(handler.command, `'${shimPath}' 'running'`);
  assert.equal(handler.args, undefined);
  assert.equal(handler.timeout, 5);
  assert.equal(handler.async, true);
  assert.equal(shimPathFor(hookPath), shimPath);
});

test('minimal keeps only the long-standing events and still covers every state', () => {
  const result = mergeRettoHooks({}, hookPath, { minimal: true });
  assert.deepEqual(
    Object.keys(result.hooks).sort(),
    REQUIRED_EVENT_STATES.map((entry) => entry.event).sort()
  );
  const states = new Set(REQUIRED_EVENT_STATES.map((entry) => entry.state));
  for (const state of ['idle', 'running', 'waiting', 'waving']) {
    assert.ok(states.has(state), `필수 이벤트가 ${state} 를 못 만든다`);
  }
});

test('installs hooks for concurrent sessions, task progress, and user input', () => {
  const result = mergeRettoHooks({}, hookPath);
  for (const event of ['PostToolBatch', 'Elicitation', 'SubagentStart', 'SubagentStop', 'TaskCreated', 'TaskCompleted']) {
    assert.ok(result.hooks[event], `missing ${event}`);
  }
});

test('merges supported Codex lifecycle hooks without replacing neighbors', () => {
  const existing = {
    description: 'mine',
    hooks: {
      Stop: [{ hooks: [{ type: 'command', command: 'announce' }] }]
    }
  };
  const result = mergeRettoCodexHooks(existing, hookPath);
  assert.equal(result.description, 'mine');
  assert.equal(result.hooks.Stop[0].hooks[0].command, 'announce');
  assert.equal(result.hooks.Stop.length, 2);
  assert.deepEqual(Object.keys(result.hooks).sort(), CODEX_EVENT_STATES.map((entry) => entry.event).sort());
  const command = result.hooks.UserPromptSubmit[0].hooks[0].command;
  assert.equal(command, `'${shimPath}' 'running' 'codex'`);
  assert.equal(result.hooks.UserPromptSubmit[0].hooks[0].timeout, 5);
  assert.equal(result.hooks.UserPromptSubmit[0].hooks[0].async, true);
  assert.equal(result.hooks.SessionEnd[0].hooks[0].timeout, 3);
  assert.equal(result.hooks.SessionEnd[0].hooks[0].async, false);
});

test('Codex hook install is idempotent and removal keeps other hooks', () => {
  const first = mergeRettoCodexHooks({}, hookPath);
  const second = mergeRettoCodexHooks(first, hookPath);
  for (const entry of CODEX_EVENT_STATES) {
    const handlers = second.hooks[entry.event]
      .flatMap((group) => group.hooks || [])
      .filter((handler) => handler.command?.includes(shimPath) && handler.command.includes("'codex'"));
    assert.equal(handlers.length, 1, entry.event);
  }
  second.hooks.Stop.unshift({ hooks: [{ type: 'command', command: 'announce' }] });
  const removed = removeRettoCodexHooks(second, hookPath);
  assert.deepEqual(removed.hooks.Stop, [{ hooks: [{ type: 'command', command: 'announce' }] }]);
});

test('Codex removal leaves Claude entries alone', () => {
  // Codex 판별은 명령줄 끝의 'codex' 까지 봐야 한다. 그냥 경로만 보면
  // 두 설정이 같은 파일에 있을 때 Claude 항목까지 함께 빠진다.
  const claudeOnly = mergeRettoHooks({}, hookPath);
  const kept = removeRettoCodexHooks(claudeOnly, hookPath);
  assert.deepEqual(Object.keys(kept.hooks).sort(), Object.keys(claudeOnly.hooks).sort());
});
