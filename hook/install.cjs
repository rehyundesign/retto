#!/usr/bin/env node
// 레토가 Claude Code 상태를 알 수 있게 훅을 설치한다.
//   node install.cjs            설치·갱신
//   node install.cjs --uninstall  제거
//
// 하는 일 두 가지다.
//   1. hook.cjs 를 ~/.claude/retto-pet/ 로 복사
//   2. ~/.claude/settings.json 에 이벤트 17개를 등록 (다른 훅은 건드리지 않는다)
// settings.json 은 고치기 전에 백업한다.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { installClaudeHooks, uninstallClaudeHooks } = require('./lib/hook-settings');

/// 설정에 박을 node 경로. process.execPath 는 버전이 든 실경로(.../Cellar/node/26.6.0/bin/node)라
/// brew 로 node 를 올리면 사라진다. 버전이 안 든 안정적인 자리를 먼저 쓴다.
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

try {
  migrateLegacyPetDir();
  if (process.argv.includes('--uninstall')) {
    uninstallClaudeHooks({ settingsPath, installedHookPath });
    console.log(`레토 훅을 제거했습니다 · ${settingsPath}`);
  } else {
    // 설정에는 절대 경로가 들어가야 한다. GUI 로 띄운 Claude Code 는 PATH 가 거의 비어 있다.
    installClaudeHooks({
      settingsPath,
      packagedHookPath,
      installedHookPath,
      nodeCommand: stableNodePath()
    });
    console.log(`레토 훅을 설치했습니다 · ${installedHookPath}\n  node: ${stableNodePath()}\n  설정: ${settingsPath}`);
  }
} catch (error) {
  console.error(`실패: ${error && error.message ? error.message : error}`);
  process.exit(1);
}
