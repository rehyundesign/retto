#!/bin/zsh
# 레토가 왜 안 움직이는지 한 번에 본다.
#
# 있는 이유는 하나다 — 훅이 한 번도 돈 적이 없어도 레토 화면은 정상 대기와 똑같다.
# 받아 간 사람이 알려 줄 수 있는 건 "쳐다만 보고 있다" 뿐이라, 어디서 멈췄는지
# 물어보는 데 카톡을 여러 번 왕복했다. 이걸 돌리고 출력을 그대로 보내면 된다.
#
# 아무것도 고치지 않고 읽기만 한다.
set -uo pipefail
# 맞는 파일이 없는 glob 을 오류로 만들지 않는다. zsh 기본값이라 여기서 꺼 둔다.
setopt null_glob

print -r -- "── 레토 진단 ──"
print -r -- "macOS $(sw_vers -productVersion) · $(uname -m)"

APP="$HOME/Applications/Retto Claude Pet.app"
if [[ -d "$APP" ]]; then
  print -r -- "앱          $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '버전 못 읽음')"
else
  print -r -- "앱          ✗ ~/Applications 에 없습니다"
fi
if pgrep -f "Claude Pet.app/Contents/MacOS" >/dev/null 2>&1; then
  print -r -- "실행        돌고 있습니다"
else
  print -r -- "실행        ✗ 떠 있지 않습니다"
fi

# node. hook.sh 가 찾는 자리와 같은 순서로 본다.
NODE=""
for candidate in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node \
  "$(command -v node 2>/dev/null || true)" \
  "$HOME"/.volta/bin/node "$HOME"/.fnm/aliases/default/bin/node \
  "$HOME"/.nvm/versions/node/*/bin/node; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then NODE="$candidate"; break; fi
done
if [[ -n "$NODE" ]]; then
  print -r -- "node        $("$NODE" -v 2>/dev/null) · $NODE"
else
  print -r -- "node        ✗ 없습니다 — https://nodejs.org 에서 설치해 주세요"
fi

# 훅 파일과 등록 상태.
PET="$HOME/.claude/retto-pet"
[[ -x "$PET/hook.sh" ]] && print -r -- "훅 실행기    있음" || print -r -- "훅 실행기    ✗ 없습니다 — 설치.command 를 다시 실행해 주세요"
[[ -f "$PET/hook.cjs" ]] && print -r -- "훅 본체      있음" || print -r -- "훅 본체      ✗ 없습니다 — 설치.command 를 다시 실행해 주세요"

if [[ -n "$NODE" ]]; then
  "$NODE" - "$HOME" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const home = process.argv[2];
// 한글은 터미널에서 두 칸을 쓴다. 글자 수로 맞추면 셸에서 찍은 줄과 열이 어긋난다.
const width = (text) => [...text].reduce((sum, ch) => sum + (ch.codePointAt(0) > 0x1100 ? 2 : 1), 0);
const pad = (label) => label + ' '.repeat(Math.max(1, 12 - width(label)));

function readJSON(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return undefined; }
}

const settingsPath = path.join(home, '.claude', 'settings.json');
if (!fs.existsSync(settingsPath)) {
  console.log(pad('훅 등록') + '✗ ~/.claude/settings.json 이 없습니다');
} else {
  const settings = readJSON(settingsPath);
  if (!settings) {
    console.log(pad('훅 등록') + '✗ settings.json 을 읽지 못했습니다 — JSON 이 깨졌습니다');
  } else {
    const marker = /ret{1,2}o-pet\/hook\./;
    const mine = Object.entries(settings.hooks || {}).flatMap(([event, groups]) =>
      (groups || []).flatMap((group) => (group.hooks || [])
        .filter((handler) => marker.test(JSON.stringify(handler)))
        .map((handler) => ({ event, handler }))));
    if (mine.length === 0) {
      console.log(pad('훅 등록') + '✗ 레토 훅이 없습니다');
    } else {
      const shapes = new Set(mine.map(({ handler }) => Array.isArray(handler.args) ? '옛 모양(command+args)' : 'command 한 줄'));
      console.log(pad('훅 등록') + `${mine.length}개 이벤트 · ${[...shapes].join(', ')}`);
    }
  }
}

// 터미널과 Claude 앱은 각자 claude-code 를 쓴다. 버전이 갈리면 한쪽만 동작하지 않는다.
function newest(directory) {
  try {
    return fs.readdirSync(directory)
      .filter((name) => /^\d+\.\d+\.\d+/.test(name))
      .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
      .pop();
  } catch { return undefined; }
}
const cli = newest(path.join(home, '.local', 'share', 'claude', 'versions'));
const app = newest(path.join(home, 'Library', 'Application Support', 'Claude', 'claude-code'));
console.log(pad('claude-code') + `터미널 ${cli || '없음'} · Claude 앱 ${app || '없음'}`);

const registryPath = path.join(home, '.claude', 'retto-pet', 'sessions.json');
const registry = readJSON(registryPath);
if (!registry) {
  console.log(pad('소식') + '✗ 기록이 없습니다 — 훅이 한 번도 돈 적이 없습니다');
} else {
  const labels = { vscode: 'VS Code', claude: 'Claude 앱', cli: '터미널', codex: 'Codex' };
  const latest = {};
  for (const record of Object.values(registry.sessions || {})) {
    const key = record.source === 'codex' ? 'codex' : record.client;
    if (!labels[key]) continue;
    const at = record.updatedAtMs || 0;
    if (!latest[key] || latest[key] < at) latest[key] = at;
  }
  console.log(pad('소식'));
  for (const [key, label] of Object.entries(labels)) {
    const at = latest[key];
    const since = at ? `${Math.round((Date.now() - at) / 60000)}분 전` : '없음';
    console.log('  ' + pad(label) + since);
  }
}
JS
fi

print -r -- "───────────"
print -r -- "이 내용을 그대로 보내 주시면 됩니다. 창을 닫아도 됩니다."
