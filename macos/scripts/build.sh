#!/bin/zsh
# 레토 macOS 오버레이를 빌드한다. --install 을 붙이면 ~/Applications 에 넣고 다시 띄운다.
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_ROOT="${PROJECT_DIR:h}"
ASSETS_DIR="$APP_ROOT/assets"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$APP_ROOT/dist"
VERSION="0.5.0"
APP_NAME="Retto Claude Pet.app"
# 0.4.0 까지는 "Reto Claude Pet.app" 이었다. 영어 표기를 Retto 로 맞추면서 이름이 바뀌었으니,
# 설치할 때 옛 이름 앱을 함께 걷어낸다. 그대로 두면 둘이 같이 떠서 말풍선이 두 개가 된다.
LEGACY_APP_NAME="Reto Claude Pet.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/RettoIcon.iconset"

INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR" "$DIST_DIR"

swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework ServiceManagement \
  "$PROJECT_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/RettoClaudePet"

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

# 같은 버전으로 여러 번 빌드해 보내면 친구가 받은 게 어떤 것인지 알 방법이 없다.
# 그래서 번들에 들어가는 Info.plist 에만 버전을 찍는다 — 원본은 건드리지 않으니
# 빌드할 때마다 git 이 더러워지지 않고, 버전을 손으로 두 군데 맞출 일도 없다.
#   버전   VERSION 하나가 원천
#   빌드   커밋 수. 히스토리를 따라 저절로 올라간다
#   스탬프 언제·어떤 커밋으로 만들었는지. 커밋 뒤 고친 게 있으면 해시에 + 가 붙는다
BUILD_NUMBER="$(git -C "$APP_ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
GIT_SHA="$(git -C "$APP_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git -C "$APP_ROOT" diff --quiet HEAD -- "$APP_ROOT" 2>/dev/null; then
  GIT_SHA="$GIT_SHA+"
fi
BUILD_STAMP="$(date '+%Y-%m-%d %H:%M') · $GIT_SHA"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :RettoBuildStamp" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :RettoBuildStamp string $BUILD_STAMP" "$CONTENTS_DIR/Info.plist"
echo "stamp: $VERSION ($BUILD_NUMBER) · $BUILD_STAMP"
cp "$ASSETS_DIR/spritesheet.webp" "$RESOURCES_DIR/spritesheet.webp"
# 스킨 아틀라스. 발바닥 메뉴 "스킨" 이 이걸 갈아 끼운다. 없으면 기본 스킨만 뜬다.
for skin in spritesheet-angel; do
  [ -f "$ASSETS_DIR/$skin.webp" ] && cp "$ASSETS_DIR/$skin.webp" "$RESOURCES_DIR/$skin.webp"
done
cp "$ASSETS_DIR/NanumMiNiSonGeurSsi.ttf" "$RESOURCES_DIR/NanumMiNiSonGeurSsi.ttf"
# 훅을 앱에 넣어 둔다. 발바닥 메뉴의 "Claude 훅 설치·갱신" 이 이걸 쓴다.
rm -rf "$RESOURCES_DIR/hook"
mkdir -p "$RESOURCES_DIR/hook"
cp "$APP_ROOT/hook/hook.cjs" "$APP_ROOT/hook/install.cjs" "$RESOURCES_DIR/hook/"
cp -R "$APP_ROOT/hook/lib" "$RESOURCES_DIR/hook/lib"

for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  size="${spec%% *}"
  name="${spec#* }"
  sips -z "$size" "$size" "$ASSETS_DIR/icon.png" --out "$ICONSET_DIR/$name" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/RettoIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

"$MACOS_DIR/RettoClaudePet" --self-test

rm -rf "$DIST_DIR/$APP_NAME"
cp -R "$APP_DIR" "$DIST_DIR/$APP_NAME"

# 베타를 남에게 보낼 때 필요한 것을 한 폴더에 담아 zip 하나로 만든다.
# 애드혹 서명이라 받는 쪽이 격리 딱지를 떼야 열리므로, 그 일을 하는 설치기와
# 안내문을 앱과 같이 넣는다. 앱만 보내면 상대는 "손상되었습니다" 만 보고 끝난다.
SHARE_DIR="$DIST_DIR/share/레토 $VERSION"
rm -rf "$DIST_DIR/share"
mkdir -p "$SHARE_DIR"
cp -R "$APP_DIR" "$SHARE_DIR/$APP_NAME"
cp "$APP_ROOT/scripts/beta-install.command" "$SHARE_DIR/설치.command"
chmod +x "$SHARE_DIR/설치.command"
sed "s/__VERSION__/$VERSION/g" "$APP_ROOT/scripts/beta-readme.txt" > "$SHARE_DIR/먼저-읽어주세요.txt"
rm -f "$DIST_DIR/Retto-Claude-Pet-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$SHARE_DIR" "$DIST_DIR/Retto-Claude-Pet-$VERSION.zip"
rm -rf "$DIST_DIR/share"

if (( INSTALL )); then
  # 앱 이름(Reto→Retto)과 실행파일 이름(RetoClaudePet→RettoClaudePet)이 차례로 바뀌었다.
  # 옛 조합으로 돌고 있는 것까지 내려야 새 것을 덮어쓸 수 있다.
  pkill -f "Reto Claude Pet.app/Contents/MacOS/RetoClaudePet" || true
  pkill -f "Retto Claude Pet.app/Contents/MacOS/RetoClaudePet" || true
  pkill -f "Retto Claude Pet.app/Contents/MacOS/RettoClaudePet" || true
  sleep 1
  rm -rf "$HOME/Applications/$APP_NAME"
  cp -R "$APP_DIR" "$HOME/Applications/$APP_NAME"
  # 옛 이름으로 깔려 있던 것을 지운다. 새 것이 제대로 놓인 뒤에만 손댄다.
  if [[ -d "$HOME/Applications/$LEGACY_APP_NAME" && -d "$HOME/Applications/$APP_NAME" ]]; then
    rm -rf "$HOME/Applications/$LEGACY_APP_NAME"
    echo "removed legacy: $HOME/Applications/$LEGACY_APP_NAME"
  fi
  # 앱을 새로 깔 때 훅도 같이 최신으로 맞춘다
  "$APP_ROOT/scripts/install-hooks.sh" || echo "훅 설치를 건너뛰었습니다 (node 없음?)"
  open "$HOME/Applications/$APP_NAME"
  echo "installed: $HOME/Applications/$APP_NAME"
fi

echo "$APP_DIR"
