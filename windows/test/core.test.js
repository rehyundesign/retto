const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const core = require('../src/core');
const setupCheck = require('../src/setup-check');

const now = Date.parse('2026-11-03T12:00:00Z');
const minutes = (n) => n * 60 * 1000;

function session(id, state, ageMinutes, extra = {}) {
  return core.normalizeSession(id, {
    sessionId: id,
    state,
    updatedAt: new Date(now - minutes(ageMinutes)).toISOString(),
    attention: ['waiting', 'failed', 'waving'].includes(state),
    ...extra
  });
}

function choose(sessions, options = {}) {
  return core.chooseView({ sessions, seen: {}, pinnedId: null, nowMs: now, trackingStartedAtMs: now - minutes(5), ...options });
}

test('every state has an animation inside the 12-row atlas', () => {
  for (const state of core.STATES) {
    const animation = core.ANIMATIONS[state];
    assert.ok(animation, state);
    assert.ok(animation.row >= 0 && animation.row < core.SPRITE.rows, state);
    assert.ok(core.TONES[animation.tone], state);
  }
});

test('waiting for input beats a finished turn, which beats work in progress', () => {
  const view = choose([session('a', 'running', 1), session('b', 'waving', 2), session('c', 'waiting', 3)]);
  assert.equal(view.selected.id, 'c');
  assert.deepEqual(view.sessions.map((item) => item.id), ['c', 'b', 'a']);
});

test('the badge counts only finished turns nobody has looked at', () => {
  const view = choose([session('a', 'waving', 1), session('b', 'waiting', 1), session('c', 'waving', 2)], { seen: { c: now } });
  assert.equal(view.badgeCount, 1);
  assert.equal(view.badgeSessions[0].id, 'a');
});

test('a seen alert drops to idle, but new work after it shows again', () => {
  assert.equal(core.displayState('waving', now - 1000, now, undefined, now), 'idle');
  assert.equal(core.displayState('running', now, now - 1000, undefined, now), 'running');
});

test('silent "working" turns into idle after ten minutes unless the transcript keeps growing', () => {
  assert.equal(core.displayState('running', now - minutes(11), undefined, undefined, now), 'idle');
  assert.equal(core.displayState('running', now - minutes(11), undefined, now - minutes(1), now), 'running');
});

test('a pin holds until something needs you', () => {
  const quiet = choose([session('a', 'idle', 1), session('b', 'running', 1)], { pinnedId: 'a' });
  assert.equal(quiet.selected.id, 'a');
  const urgent = choose([session('a', 'idle', 1), session('b', 'waiting', 1)], { pinnedId: 'a' });
  assert.equal(urgent.selected.id, 'b');
  assert.equal(urgent.keepPin, true);
  const gone = choose([session('b', 'idle', 1)], { pinnedId: 'a' });
  assert.equal(gone.keepPin, false);
});

test('Retto sleeps when everything is quiet for ten minutes, and when nothing exists', () => {
  assert.equal(choose([session('a', 'idle', 11)]).pose, 'sleeping');
  assert.equal(choose([session('a', 'idle', 5)]).pose, 'idle');
  const empty = choose([]);
  assert.equal(empty.pose, 'sleeping');
  assert.equal(empty.selected, undefined);
});

test('news from long before the app started is treated as already read', () => {
  const view = choose([session('old', 'waving', 120)], { trackingStartedAtMs: now });
  assert.equal(view.badgeCount, 0);
  assert.ok(view.newlySeen.old);
});

test('names: confirmed titles only, and a Windows cwd still gives the folder name', () => {
  assert.equal(core.sessionTitle({ displayTitle: 'B' }), 'No name');
  assert.equal(core.sessionTitle({ displayTitle: '랜딩 고치기' }), '랜딩 고치기');
  assert.equal(core.projectName({ cwd: 'C:\\Users\\me\\retto' }), 'retto');
  assert.equal(core.projectName({ cwd: '/Users/me/retto' }), 'retto');
  assert.match(core.menuLabel({ state: 'waiting', client: 'vscode', cwd: 'C:\\w\\app', sessionTitle: '빌드 고치기' }), /^● 기다림 {2}빌드 고치기 · app · VS Code$/);
});

test('a half-written registry is ignored instead of wiping the sessions', () => {
  assert.equal(core.readRegistry('{"version":1,"sessions":{"a":'), null);
  assert.deepEqual(core.readRegistry('{"version":1,"sessions":{}}'), []);
});

test('setup check counts Retto hooks written with Windows backslashes or slashes, and keeps Codex apart', () => {
  const settings = {
    hooks: {
      Stop: [{ hooks: [
        { type: 'command', command: 'node "C:/Users/me/.claude/retto-pet/hook.cjs" "waving"' },
        { type: 'command', command: 'node "C:\\Users\\me\\.claude\\retto-pet\\hook.cjs" "idle"' },
        { type: 'command', command: 'node "C:/Users/me/.claude/retto-pet/hook.cjs" "waving" "codex"' },
        { type: 'command', command: 'echo neighbor' }
      ] }]
    }
  };
  assert.equal(setupCheck.countRettoHooks(settings), 2);
  assert.equal(setupCheck.countRettoHooks(settings, { codex: true }), 1);
});

test('setup check reports each missing piece separately', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'retto-home-'));
  const report = setupCheck.inspect({ home });
  assert.ok(report.problems.includes('훅 없음'));
  assert.ok(report.problems.includes('소식 없음'));
  assert.equal(report.codexInstalled, false);
});

test('VS Code folder links keep # and spaces inside the path', () => {
  assert.equal(core.vscodeFolderUrl('C:\\work\\app'), 'vscode://file/C:/work/app/');
  assert.equal(core.vscodeFolderUrl('C:\\work\\c#app'), 'vscode://file/C:/work/c%23app/');
  assert.equal(core.vscodeFolderUrl('C:\\Users\\레토 사용자\\a'), `vscode://file/C:/Users/${encodeURIComponent('레토 사용자')}/a/`);
  assert.equal(core.vscodeFolderUrl('/Users/me/app'), 'vscode://file/Users/me/app/');
});

test('old news is already read on the very first pass, so Retto does not wave at startup', () => {
  // 두 시간 전에 끝난 일이라 손을 흔들지 않고, 다른 소식도 없으니 잔다.
  const view = choose([session('old', 'waving', 120)], { trackingStartedAtMs: now });
  assert.equal(view.pose, 'sleeping');
  assert.equal(view.selected.visibleState, 'idle');
});
