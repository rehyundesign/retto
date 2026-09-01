#!/usr/bin/env node
// 레토가 Claude Code와 Codex 상태를 알 수 있게 훅을 설치한다.
//   node install.cjs              설치·갱신
//   node install.cjs --minimal    오래된 이벤트 여덟 개만 등록
//   node install.cjs --full       열일곱 개 전부 등록 (버전 확인을 넘긴다)
//   node install.cjs --codex      Codex 훅을 무조건 등록
//   node install.cjs --no-codex   Codex 훅을 등록하지 않는다
//   node install.cjs --uninstall  제거
//
// 하는 일 네 가지다.
//   1. hook.cjs 를 ~/.claude/retto-pet/ 로 복사
//   2. hook.sh(node 를 찾아 주는 실행기)를 같은 자리에 깔고 실행 권한을 준다
//   3. ~/.claude/settings.json 에 이벤트를 등록 (다른 훅은 건드리지 않는다)
//   4. ~/.codex/ 를 쓰는 사람에게만 Codex lifecycle 이벤트를 등록 (다른 훅은 건드리지 않는다)
// 두 설정 파일은 고치기 전에 백업한다.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { decideEventScope, eventCountFor } = require('./lib/claude-versions');
const {
  installClaudeHooks,
  installCodexHooks,
  shimPathFor,
  uninstallClaudeHooks,
  uninstallCodexHooks
} = require('./lib/hook-settings');

/// hook.sh 에 적어 둘 node 경로. process.execPath 는 버전이 든 실경로
/// (.../Cellar/node/26.6.0/bin/node, .../.nvm/versions/node/v22.1.0/bin/node)라
/// 버전을 올리면 사라진다. 버전이 안 든 안정적인 자리를 먼저 쓴다.
/// 여기서 고른 경로가 나중에 사라져도 hook.sh 가 다른 자리를 찾아본다.
function stableNodePath() {
  for (const candidate of ['/opt/homebrew/bin/node', '/usr/local/bin/node', '/usr/bin/node']) {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {}
  }
  return process.execPath;
}

const settingsPath = path.join(os.homedir(), '.claude', 'settings.json');
const codexHooksPath = path.join(os.homedir(), '.codex', 'hooks.json');
const petDir = path.join(os.homedir(), '.claude', 'retto-pet');
const legacyPetDir = path.join(os.homedir(), '.claude', 'reto-pet');
const installedHookPath = path.join(petDir, 'hook.cjs');

/// 옛 폴더(reto-pet)에 쌓인 세션 기록을 새 폴더로 데려온다.
/// 통째로 rename 하지 않는 이유는, 새 폴더가 이미 있으면 그걸 덮어쓰기 때문이다.
function migrateLegacyPetDir() {
  if (!fs.existsSync(legacyPetDir) || legacyPetDir === petDir) return;
  fs.mkdirSync(petDir, { recursive: true });
  for (const name of ['sessions.json', 'state.json']) {
    const from = path.join(legacyPetDir, name);
    const to = path.join(petDir, name);
    if (fs.existsSync(from) && !fs.existsSync(to)) fs.copyFileSync(from, to);
  }
  fs.rmSync(legacyPetDir, { recursive: true, force: true });
  console.log(`옛 폴더를 옮겼습니다 · ${legacyPetDir} → ${petDir}`);
}
const packagedHookPath = path.join(__dirname, 'hook.cjs');
const packagedShimPath = path.join(__dirname, 'hook.sh');

/// Codex 를 쓰는 사람인가. 쓰지도 않는 사람 홈에 ~/.codex/hooks.json 을 새로 만들 이유가 없다.
/// 물어보지 않는 이유는 홈 폴더에 답이 이미 있어서다.
function decideCodex(argv) {
  if (argv.includes('--codex')) return { install: true, reason: '--codex 로 지정했습니다' };
  if (argv.includes('--no-codex')) return { install: false, reason: '--no-codex 로 지정했습니다' };
  const exists = fs.existsSync(path.join(os.homedir(), '.codex'));
  return exists
    ? { install: true, reason: '설치 뒤 Codex 를 한 번 다시 켜서 훅 승인 화면에서 허용해 주세요' }
    : { install: false, reason: '~/.codex 가 없어 건너뜁니다' };
}

try {
  migrateLegacyPetDir();
  if (process.argv.includes('--uninstall')) {
    uninstallClaudeHooks({ settingsPath, installedHookPath });
    uninstallCodexHooks({ hooksPath: codexHooksPath, installedHookPath });
    for (const leftover of [shimPathFor(installedHookPath), installedHookPath]) {
      fs.rmSync(leftover, { force: true });
    }
    console.log(`레토 훅을 제거했습니다\n  Claude: ${settingsPath}\n  Codex: ${codexHooksPath}`);
  } else {
    const nodeCommand = stableNodePath();
    const { minimal, reason } = decideEventScope(process.argv);
    const { installedShimPath } = installClaudeHooks({
      settingsPath,
      packagedHookPath,
      packagedShimPath,
      installedHookPath,
      nodeCommand,
      minimal
    });
    const codex = decideCodex(process.argv);
    if (codex.install) installCodexHooks({ hooksPath: codexHooksPath, installedHookPath });
    const count = eventCountFor(minimal);
    console.log([
      `레토 훅을 설치했습니다 · ${installedShimPath}`,
      `  이벤트: ${count}개 — ${reason}`,
      `  node: ${nodeCommand}`,
      `  Claude: ${settingsPath}`,
      `  Codex: ${codex.install ? codexHooksPath : '등록 안 함'} — ${codex.reason}`
    ].join('\n'));
  }
} catch (error) {
  console.error(`실패: ${error && error.message ? error.message : error}`);
  process.exit(1);
}
