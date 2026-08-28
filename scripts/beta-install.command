#!/bin/zsh
# 레토 베타 설치기. 받는 사람이 터미널에 끌어다 놓고 엔터 치면 되는 파일이다.
#
# 있는 이유는 하나다 — 앱이 애드혹 서명(Developer ID·공증 없음)이라,
# 내려받은 앱에 붙은 격리 딱지(com.apple.quarantine)를 떼지 않으면
# macOS 가 "손상되었기 때문에 열 수 없습니다" 로 막는다. 그 일을 여기서 한다.
#
# 이 파일 자체는 셸 스크립트라 Gatekeeper 검사를 받지 않는다.
# 그래서 격리된 폴더에서 그냥 실행해도 된다.
set -uo pipefail

SCRIPT_DIR="${0:A:h}"
APP_NAME="Retto Claude Pet.app"
# 0.4.0 까지는 "Reto Claude Pet.app" 이었다. 옛 이름으로 깔린 것이 남아 있으면
# 둘이 같이 떠서 말풍선이 두 개가 되므로 함께 걷어낸다.
LEGACY_APP_NAME="Reto Claude Pet.app"
SOURCE_APP="$SCRIPT_DIR/$APP_NAME"
TARGET_DIR="$HOME/Applications"
TARGET_APP="$TARGET_DIR/$APP_NAME"

# print -r 은 이스케이프를 해석하지 않는다. 빈 줄은 따로 찍어야 "\n" 이 그대로 보이지 않는다.
fail() {
  print -u2 -- ""
  print -r -u2 -- "✗ $1"
  print -u2 -- ""
  print -u2 -- "창을 닫아도 됩니다."
  exit 1
}

print -r -- "레토를 설치합니다."
print -r -- ""

# 1. 같은 폴더에 앱이 있어야 한다. zip 을 풀지 않고 실행하면 여기서 걸린다.
[[ -d "$SOURCE_APP" ]] || fail "같은 폴더에서 「$APP_NAME」을 찾지 못했습니다.
  zip 을 먼저 풀고, 풀린 폴더 안의 설치.command 를 실행해 주세요."

# 2. 애플 실리콘 전용으로 빌드된 앱이다(arm64). 인텔 맥에서는 아예 돌지 않는다.
if [[ "$(uname -m)" != "arm64" ]]; then
  fail "이 앱은 애플 실리콘(M1 이상) 맥 전용입니다.
  지금 맥은 인텔($(uname -m)) 이라 실행할 수 없습니다."
fi

# 3. macOS 13 (Ventura) 이상.
os_major="${$(sw_vers -productVersion)%%.*}"
if (( os_major < 13 )); then
  fail "macOS 13 (Ventura) 이상이 필요합니다. 지금은 $(sw_vers -productVersion) 입니다."
fi

# 4. 이미 돌고 있으면 내린다. 덮어쓰는 중에 살아 있으면 앱이 깨진다.
if pkill -f "Claude Pet.app/Contents/MacOS/RetoClaudePet" 2>/dev/null; then
  print -r -- "· 실행 중이던 레토를 내렸습니다"
  sleep 1
fi

# 5. ~/Applications 에 넣는다. /Applications 과 달리 권한을 물지 않는다.
mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP" || fail "앱을 복사하지 못했습니다."
print -r -- "· $TARGET_APP 에 넣었습니다"

# 6. 격리 딱지를 뗀다. 이게 이 스크립트의 본론이다.
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
print -r -- "· macOS 격리 표시를 풀었습니다"

# 6-1. 옛 이름으로 깔린 것을 지운다. 새 것이 제대로 놓인 뒤에만 손댄다.
if [[ -d "$TARGET_DIR/$LEGACY_APP_NAME" && -d "$TARGET_APP" ]]; then
  rm -rf "$TARGET_DIR/$LEGACY_APP_NAME"
  print -r -- "· 옛 이름으로 깔려 있던 앱을 걷어냈습니다"
fi

# 7. 훅을 설치한다. 이게 없으면 레토는 Claude Code 상태를 못 읽는 그림일 뿐이다.
#    GUI 앱과 같은 자리에서 node 를 찾는다 — 터미널 PATH 에 의존하지 않는다.
NODE=""
for candidate in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node "$(command -v node 2>/dev/null || true)"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then NODE="$candidate"; break; fi
done

hook_ok=0
if [[ -z "$NODE" ]]; then
  print -r -- "· ⚠ Node.js 가 없어 훅을 건너뛰었습니다"
elif "$NODE" "$TARGET_APP/Contents/Resources/hook/install.cjs"; then
  hook_ok=1
else
  print -r -- "· ⚠ 훅 설치가 실패했습니다"
fi

# 8. 띄운다.
open "$TARGET_APP"
print -r -- ""
print -r -- "✓ 설치 끝. 화면에 고양이가 나오면 성공입니다."

if (( ! hook_ok )); then
  print -r -- ""
  print -r -- "다만 훅이 안 붙었습니다. 레토가 Claude Code 상태를 읽는 통로라서,"
  print -r -- "이게 없으면 고양이는 떠 있어도 아무 반응을 하지 않습니다."
  print -r -- "Node.js (https://nodejs.org) 를 설치한 뒤 이 설치.command 를 다시 실행해 주세요."
fi

print -r -- ""
print -r -- "창을 닫아도 됩니다."
