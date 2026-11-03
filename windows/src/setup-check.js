// 「고장인지 아닌지 레토가 말해 준다」의 Windows 판. 맥 앱 ClaudeIntegration.swift · SetupWindow.swift 와 같은 셋을 본다.
//
// 1. settings.json 에 레토 훅이 몇 개 있나 → 어긋나면 「다시 설치」
// 2. 훅을 돌릴 node 가 PATH 에 있나 → 없으면 Node.js 설치
// 3. 채널(VS Code · Claude 앱 · 터미널 · Codex)별 마지막 소식 → 없으면 그 클라이언트 쪽 문제
//
// 훅이 한 번도 안 돌았는데 레토가 정상 대기처럼 자면 받은 사람은 고장인지 알 수 없다.
// 셋을 나눠 보여 주는 이유는 셋 다 손질하는 곳이 다르기 때문이다.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const HOOK_MARKERS = ['.claude/retto-pet/hook.', '.claude/reto-pet/hook.'];

function homePaths(home = os.homedir()) {
  return {
    settingsPath: path.join(home, '.claude', 'settings.json'),
    codexHooksPath: path.join(home, '.codex', 'hooks.json'),
    codexHome: path.join(home, '.codex'),
    petDir: path.join(home, '.claude', 'retto-pet')
  };
}

function readJSON(filePath) {
  try { return JSON.parse(fs.readFileSync(filePath, 'utf8')); } catch { return undefined; }
}

/// 레토 훅 개수. 경로를 슬래시로 바꿔 보므로 Windows 의 백슬래시 경로도 같이 센다.
function countRettoHooks(settings, { codex = false } = {}) {
  let count = 0;
  for (const groups of Object.values(settings?.hooks || {})) {
    if (!Array.isArray(groups)) continue;
    for (const group of groups) {
      for (const handler of group?.hooks || []) {
        const command = String(handler?.command || '').replaceAll('\\', '/');
        if (!HOOK_MARKERS.some((marker) => command.includes(marker))) continue;
        const isCodex = /(?:^|[\s'"])codex(?:$|[\s'"])/.test(command);
        if (isCodex === codex) count += 1;
      }
    }
  }
  return count;
}

/// 훅 명령은 PATH 의 `node` 를 부른다. 같은 PATH 로 찾아본다.
function findNode() {
  try {
    const finder = process.platform === 'win32' ? 'where.exe' : 'which';
    const out = execFileSync(finder, ['node'], { encoding: 'utf8', timeout: 3000, windowsHide: true });
    return out.split(/\r?\n/).find(Boolean);
  } catch {
    return undefined;
  }
}

function channelOf(session) {
  if (session.source === 'codex' || session.client === 'codex') return 'Codex';
  if (session.client === 'vscode') return 'VS Code';
  if (session.client === 'claude') return 'Claude 앱';
  if (session.client === 'cli') return '터미널';
  return '알 수 없음';
}

function lastNewsByChannel(registry) {
  const news = {};
  for (const session of Object.values(registry?.sessions || {})) {
    const at = Date.parse(session?.updatedAt || '');
    if (!Number.isFinite(at)) continue;
    const channel = channelOf(session || {});
    news[channel] = Math.max(news[channel] || 0, at);
  }
  return news;
}

function inspect({ home = os.homedir(), expectedClaudeHooks, expectedCodexHooks } = {}) {
  const paths = homePaths(home);
  const claudeHooks = countRettoHooks(readJSON(paths.settingsPath));
  const codexInstalled = fs.existsSync(paths.codexHome);
  const codexHooks = codexInstalled ? countRettoHooks(readJSON(paths.codexHooksPath), { codex: true }) : 0;
  const hookFile = fs.existsSync(path.join(paths.petDir, 'hook.cjs'));
  const node = findNode();
  const news = lastNewsByChannel(readJSON(path.join(paths.petDir, 'sessions.json')));
  const problems = [];
  if (claudeHooks === 0 || !hookFile) problems.push('훅 없음');
  else if (expectedClaudeHooks && claudeHooks < expectedClaudeHooks) problems.push('훅 일부 빠짐');
  if (!node) problems.push('node 없음');
  if (Object.keys(news).length === 0) problems.push('소식 없음');
  return {
    paths,
    claudeHooks,
    expectedClaudeHooks,
    codexInstalled,
    codexHooks,
    expectedCodexHooks,
    hookFile,
    node,
    news,
    problems
  };
}

module.exports = { countRettoHooks, findNode, inspect, lastNewsByChannel, homePaths };
