// 실제로 돌아갈 claude-code 버전을 찾아 이벤트를 몇 개까지 등록할지 정한다.
//
// 터미널과 데스크탑 앱은 서로 다른 claude-code 를 쓴다. 앱은 자기 것을 따로 내려받아
// `~/Library/Application Support/Claude/claude-code/` 에 둔다. 그래서 한 기계 안에서도
// 버전이 갈리고, 터미널에서는 레토가 움직이는데 앱에서만 멈춰 있는 일이 생긴다.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { EVENT_STATES, REQUIRED_EVENT_STATES } = require('./hook-settings');

/// 이벤트 열일곱 개가 전부 있는 것을 확인한 가장 낮은 claude-code 버전.
/// 확인한 방법은 그 바이너리 안의 이벤트 이름 목록을 직접 읽은 것이다.
/// 이보다 낮은 버전이 돌고 있으면 필수 여덟 개만 등록한다 — 모르는 이벤트 이름 하나가
/// 설정 검증에서 훅 등록 전체를 무시하게 만들 수 있다.
const VERIFIED_FULL_EVENT_VERSION = [2, 1, 247];

function parseVersion(name) {
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(String(name));
  return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : undefined;
}

function compareVersion(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left[index] !== right[index]) return left[index] - right[index];
  }
  return 0;
}

function formatVersion(version) {
  return version.join('.');
}

/// 폴더 이름이 곧 버전이다. 옛 버전 폴더가 남아 있어도 실제로 도는 것은 가장 높은 것이다.
function newestVersionIn(directory) {
  let newest;
  let entries;
  try { entries = fs.readdirSync(directory); } catch { return undefined; }
  for (const name of entries) {
    const version = parseVersion(name);
    if (version && (!newest || compareVersion(version, newest) > 0)) newest = version;
  }
  return newest;
}

function installedClaudeVersions(home = os.homedir()) {
  const found = [];
  const cli = newestVersionIn(path.join(home, '.local', 'share', 'claude', 'versions'));
  if (cli) found.push({ where: '터미널', version: cli });
  const app = newestVersionIn(path.join(home, 'Library', 'Application Support', 'Claude', 'claude-code'));
  if (app) found.push({ where: 'Claude 앱', version: app });
  return found;
}

/// 필수만 등록할지 정한다. 사용자가 직접 고른 것이 있으면 그 뜻을 지킨다.
function decideEventScope(argv = [], home = os.homedir()) {
  if (argv.includes('--full')) return { minimal: false, reason: '--full 로 지정했습니다' };
  if (argv.includes('--minimal')) return { minimal: true, reason: '--minimal 로 지정했습니다' };

  const versions = installedClaudeVersions(home);
  if (versions.length === 0) {
    return { minimal: false, reason: 'claude-code 버전을 찾지 못해 전부 등록합니다' };
  }
  const oldest = versions.reduce((low, item) => compareVersion(item.version, low.version) < 0 ? item : low);
  if (compareVersion(oldest.version, VERIFIED_FULL_EVENT_VERSION) < 0) {
    return {
      minimal: true,
      reason: `${oldest.where} 의 claude-code 가 ${formatVersion(oldest.version)} 라 필수 이벤트만 등록합니다`
        + ` (${formatVersion(VERIFIED_FULL_EVENT_VERSION)} 이상이면 전부 등록합니다)`
    };
  }
  return {
    minimal: false,
    reason: versions.map((item) => `${item.where} ${formatVersion(item.version)}`).join(' · ')
  };
}

function eventCountFor(minimal) {
  return minimal ? REQUIRED_EVENT_STATES.length : EVENT_STATES.length;
}

module.exports = {
  VERIFIED_FULL_EVENT_VERSION,
  compareVersion,
  decideEventScope,
  eventCountFor,
  formatVersion,
  installedClaudeVersions,
  newestVersionIn,
  parseVersion
};
