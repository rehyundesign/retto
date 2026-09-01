const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {
  VERIFIED_FULL_EVENT_VERSION,
  decideEventScope,
  eventCountFor,
  installedClaudeVersions,
  newestVersionIn,
  parseVersion
} = require('../lib/claude-versions');
const { EVENT_STATES, REQUIRED_EVENT_STATES } = require('../lib/hook-settings');

/// 터미널과 Claude 앱이 각각 어떤 버전을 쓰는지 흉내 낸 가짜 홈 폴더.
function fakeHome({ cli = [], app = [] }) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'retto-versions-'));
  const cliDir = path.join(home, '.local', 'share', 'claude', 'versions');
  const appDir = path.join(home, 'Library', 'Application Support', 'Claude', 'claude-code');
  for (const [directory, names] of [[cliDir, cli], [appDir, app]]) {
    if (names.length === 0) continue;
    fs.mkdirSync(directory, { recursive: true });
    for (const name of names) fs.mkdirSync(path.join(directory, name));
  }
  return home;
}

test('reads a version from a folder name and ignores what is not one', () => {
  assert.deepEqual(parseVersion('2.1.250'), [2, 1, 250]);
  assert.deepEqual(parseVersion('2.1.250-beta'), [2, 1, 250]);
  assert.equal(parseVersion('.verified'), undefined);
});

test('takes the newest folder, since old versions stay behind', () => {
  const home = fakeHome({ cli: ['2.1.241', '2.1.243', '2.1.250'] });
  assert.deepEqual(newestVersionIn(path.join(home, '.local', 'share', 'claude', 'versions')), [2, 1, 250]);
});

test('finds the terminal and the Claude app separately', () => {
  const home = fakeHome({ cli: ['2.1.250'], app: ['2.1.247'] });
  assert.deepEqual(installedClaudeVersions(home), [
    { where: '터미널', version: [2, 1, 250] },
    { where: 'Claude 앱', version: [2, 1, 247] }
  ]);
});

test('an old Claude app pulls the whole install down to the required events', () => {
  // 이것이 성연님 상황의 후보다 — 터미널은 최신인데 앱이 자기 버전을 따로 들고 있다.
  const home = fakeHome({ cli: ['2.1.250'], app: ['2.0.30'] });
  const scope = decideEventScope([], home);
  assert.equal(scope.minimal, true);
  assert.match(scope.reason, /Claude 앱/);
  assert.equal(eventCountFor(scope.minimal), REQUIRED_EVENT_STATES.length);
});

test('both up to date means every event', () => {
  const home = fakeHome({ cli: ['2.1.250'], app: ['2.1.247'] });
  const scope = decideEventScope([], home);
  assert.equal(scope.minimal, false);
  assert.equal(eventCountFor(scope.minimal), EVENT_STATES.length);
});

test('the verified floor itself counts as new enough', () => {
  const home = fakeHome({ cli: [VERIFIED_FULL_EVENT_VERSION.join('.')] });
  assert.equal(decideEventScope([], home).minimal, false);
});

test('nothing found means we do not guess downward', () => {
  const home = fakeHome({});
  const scope = decideEventScope([], home);
  assert.equal(scope.minimal, false);
  assert.match(scope.reason, /찾지 못해/);
});

test('what the person typed wins over what we detected', () => {
  const oldHome = fakeHome({ app: ['2.0.30'] });
  const newHome = fakeHome({ cli: ['2.1.250'] });
  assert.equal(decideEventScope(['--full'], oldHome).minimal, false);
  assert.equal(decideEventScope(['--minimal'], newHome).minimal, true);
});
