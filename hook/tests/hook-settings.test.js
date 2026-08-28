const test = require('node:test');
const assert = require('node:assert/strict');
const {
  EVENT_STATES,
  mergeRettoHooks,
  removeRettoHooks
} = require('../lib/hook-settings');

const hookPath = '/Users/example/.claude/retto-pet/hook.cjs';

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
    const handlers = second.hooks[entry.event]
      .flatMap((group) => group.hooks || [])
      .filter((handler) => handler.args?.includes(hookPath));
    const expected = EVENT_STATES.filter((candidate) => candidate.event === entry.event).length;
    assert.equal(handlers.length, expected);
  }
});

test('removes only Reto handlers and keeps neighboring handlers', () => {
  const settings = {
    hooks: {
      Stop: [{ hooks: [
        { type: 'command', command: 'announce' },
        { type: 'command', command: 'node', args: [hookPath, 'waving'] }
      ] }]
    }
  };
  const result = removeRettoHooks(settings, hookPath);
  assert.deepEqual(result.hooks.Stop[0].hooks, [{ type: 'command', command: 'announce' }]);
});

test('does not mutate caller settings', () => {
  const settings = { hooks: { Stop: [{ hooks: [{ type: 'command', command: 'announce' }] }] } };
  const snapshot = JSON.stringify(settings);
  mergeRettoHooks(settings, hookPath);
  assert.equal(JSON.stringify(settings), snapshot);
});

test('can pin an absolute Node.js executable for GUI-launched Claude Code', () => {
  const result = mergeRettoHooks({}, hookPath, '/opt/homebrew/bin/node');
  const handler = result.hooks.UserPromptSubmit[0].hooks[0];
  assert.equal(handler.command, '/opt/homebrew/bin/node');
  assert.deepEqual(handler.args, [hookPath, 'running']);
});

test('installs hooks for concurrent sessions, task progress, and user input', () => {
  const result = mergeRettoHooks({}, hookPath);
  for (const event of ['PostToolBatch', 'Elicitation', 'SubagentStart', 'SubagentStop', 'TaskCreated', 'TaskCompleted']) {
    assert.ok(result.hooks[event], `missing ${event}`);
  }
});
