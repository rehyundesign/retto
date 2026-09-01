#!/bin/zsh
# 레토 macOS 오버레이를 빌드한다. --install 을 붙이면 ~/Applications 에 넣고 다시 띄운다.
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_ROOT="${PROJECT_DIR:h}"
ASSETS_DIR="$APP_ROOT/assets"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$APP_ROOT/dist"
VERSION="0.9.0"
APP_NAME="Retto.app"
# 이름이 두 번 바뀌었다. 0.4.0 까지 "Reto Claude Pet.app", 0.8.0 까지 "Retto Claude Pet.app".
# 공개하면서 제품명에서 Claude 를 뺐다 — 공식 제품처럼 읽히지 않게.
# 설치할 때 옛 이름 앱을 함께 걷어낸다. 그대로 두면 둘이 같이 떠서 말풍선이 두 개가 된다.
LEGACY_APP_NAMES=("Reto Claude Pet.app" "Retto Claude Pet.app")
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/RettoIcon.iconset"

INSTALL=0
KEEP_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --keep-build) KEEP_BUILD=1 ;;
  esac
done

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR" "$DIST_DIR"

# dist 는 보낼 묶음(dmg)만 두는 자리다. Spotlight 색인에서 빼 둔다.
touch "$DIST_DIR/.metadata_never_index"

swiftc \
  -O \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework ServiceManagement \
  "$PROJECT_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/Retto"

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
for skin in spritesheet-angel spritesheet-bee spritesheet-luna spritesheet-rilakkuma; do
  [ -f "$ASSETS_DIR/$skin.webp" ] && cp "$ASSETS_DIR/$skin.webp" "$RESOURCES_DIR/$skin.webp"
done
cp "$ASSETS_DIR/NanumMiNiSonGeurSsi.ttf" "$RESOURCES_DIR/NanumMiNiSonGeurSsi.ttf"
# 훅을 앱에 넣어 둔다. 설치기와 「레토 제거」 가 이걸 쓴다.
rm -rf "$RESOURCES_DIR/hook"
mkdir -p "$RESOURCES_DIR/hook"
cp "$APP_ROOT/hook/hook.cjs" "$APP_ROOT/hook/hook.sh" "$APP_ROOT/hook/install.cjs" "$RESOURCES_DIR/hook/"
chmod +x "$RESOURCES_DIR/hook/hook.sh"
cp -R "$APP_ROOT/hook/lib" "$RESOURCES_DIR/hook/lib"

for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  size="${spec%% *}"
  name="${spec#* }"
  sips -z "$size" "$size" "$ASSETS_DIR/icon.png" --out "$ICONSET_DIR/$name" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/RettoIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

"$MACOS_DIR/Retto" --self-test

# dist 에는 dmg 만 둔다. 예전에는 앱을 한 벌 더 풀어 뒀는데 쓰는 데가 없었고,
# Spotlight 에서 레토를 찾으면 설치본과 이것이 같이 떠서 무엇을 눌러야 할지 알 수 없었다.
rm -rf "$DIST_DIR/$APP_NAME"

# 베타를 보낼 묶음. dmg 하나다.
#
# 예전에는 zip 에 앱과 설치.command 를 넣고 "터미널 창으로 끌어다 놓으세요" 라고 했다.
# 그 파일이 하던 일은 격리 딱지를 떼는 것 하나였는데, 받는 쪽에서 그 한 줄이 가장 큰 벽이었다.
# dmg 로 바꾸면 맥에서 늘 하던 대로 끌어다 놓으면 된다.
#
# 다만 애드혹 서명이라 첫 실행에서 Gatekeeper 가 한 번 막는다. macOS 15 부터는
# 우클릭 → 열기 우회가 없어져서, 시스템 설정 > 개인정보 보호 및 보안 에서
# 「그래도 열기」를 눌러야 한다. 그 단계는 애플 개발자 서명·공증 없이는 없앨 수 없다.
STAGE_DIR="$DIST_DIR/dmg/레토 $VERSION"
rm -rf "$DIST_DIR/dmg"
mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/$APP_NAME"
# 개인 스킨은 남에게 보내는 묶음에서 뺀다. 내 기기에서는 그대로 쓴다.
# 무엇이 개인 것인지는 git 이 안다 — .gitignore 에 올려 둔 에셋이 그것이다.
# (리락쿠마처럼 남의 캐릭터로 만든 스킨이 여기 해당한다.)
for skin in "$ASSETS_DIR"/spritesheet-*.webp; do
  [ -f "$skin" ] || continue
  if git -C "$APP_ROOT" check-ignore -q "$skin" 2>/dev/null; then
    rm -f "$STAGE_DIR/$APP_NAME/Contents/Resources/$(basename "$skin")"
    echo "share: 개인 스킨 제외 $(basename "$skin")"
  fi
done

# 서명은 번들 안의 파일 목록까지 봉인한다. 위에서 스킨을 하나 뺐으므로 다시 서명해야
# 한다. 이걸 빠뜨리면 받는 쪽에서 "손상되었습니다" 가 뜬다 — 격리 딱지를 떼도 마찬가지다.
codesign --force --deep --sign - "$STAGE_DIR/$APP_NAME"
codesign --verify --deep --strict "$STAGE_DIR/$APP_NAME" || {
  echo "보낼 앱의 서명이 깨졌습니다" >&2
  exit 1
}

# 끌어다 놓을 자리. 이 링크가 없으면 어디에 넣어야 하는지 알 수 없다.
ln -s /Applications "$STAGE_DIR/Applications"
# 앱이 안 열릴 때 어디서 멈췄는지 볼 수 있게 같이 넣는다.
cp "$APP_ROOT/scripts/doctor.command" "$STAGE_DIR/진단.command"
chmod +x "$STAGE_DIR/진단.command"
sed "s/__VERSION__/$VERSION/g" "$APP_ROOT/scripts/beta-readme.txt" > "$STAGE_DIR/먼저-읽어주세요.txt"

DMG_PATH="$DIST_DIR/Retto-$VERSION.dmg"
rm -f "$DMG_PATH"
# 창 배치(아이콘 자리·크기)는 Finder 를 움직여야 정해진다. 자동화 권한이 없으면
# 그 단계만 건너뛰고 dmg 는 그대로 만든다 — 배치가 없어도 설치는 된다.
RW_DMG="$DIST_DIR/dmg/rw.dmg"
hdiutil create -volname "레토 $VERSION" -srcfolder "$STAGE_DIR" -ov -format UDRW "$RW_DMG" >/dev/null
MOUNT_DIR="$(hdiutil attach "$RW_DMG" -nobrowse -noverify -noautoopen | grep -o '/Volumes/.*' | head -1)"
if [[ -n "$MOUNT_DIR" ]]; then
  if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
  tell disk "레토 $VERSION"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set position of item "$APP_NAME" of container window to {150, 170}
    set position of item "Applications" of container window to {450, 170}
    set position of item "먼저-읽어주세요.txt" of container window to {150, 320}
    set position of item "진단.command" of container window to {450, 320}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT
  then
    echo "dmg: 창 배치를 넣었습니다"
  else
    echo "dmg: 창 배치는 건너뜁니다 (Finder 자동화 권한 없음) — 설치에는 지장이 없습니다"
  fi
  hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true
fi
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -rf "$DIST_DIR/dmg"
echo "share: $DMG_PATH"

if (( INSTALL )); then
  # 앱 이름과 실행파일 이름이 차례로 바뀌었다. 옛 조합으로 돌고 있는 것까지 내려야
  # 새 것을 덮어쓸 수 있다.
  pkill -f "Claude Pet.app/Contents/MacOS/Ret" || true
  pkill -f "Retto.app/Contents/MacOS/Retto" || true
  sleep 1
  rm -rf "$HOME/Applications/$APP_NAME"
  cp -R "$APP_DIR" "$HOME/Applications/$APP_NAME"
  # 옛 이름으로 깔려 있던 것을 지운다. 새 것이 제대로 놓인 뒤에만 손댄다.
  # /Applications 도 본다 — dmg 에서 끌어다 놓으면 그쪽에 들어간다.
  if [[ -d "$HOME/Applications/$APP_NAME" ]]; then
    for legacy in "${LEGACY_APP_NAMES[@]}"; do
      for base in "$HOME/Applications" /Applications; do
        if [[ -d "$base/$legacy" ]]; then
          rm -rf "$base/$legacy"
          echo "removed legacy: $base/$legacy"
        fi
      done
    done
  fi
  # 앱을 새로 깔 때 훅도 같이 최신으로 맞춘다
  "$APP_ROOT/scripts/install-hooks.sh" || echo "훅 설치를 건너뛰었습니다 (node 없음?)"
  open "$HOME/Applications/$APP_NAME"
  echo "installed: $HOME/Applications/$APP_NAME"
fi

# 빌드 자리에 앱을 남겨 두면 Spotlight 에서 레토를 찾았을 때 설치본과 나란히 떠서
# 무엇을 눌러야 할지 알 수 없다. `.metadata_never_index` 로는 걸러지지 않았다.
# 보낼 것은 dmg 에, 쓸 것은 ~/Applications 에 있으니 여기 남길 이유가 없다.
# 갓 빌드한 것을 직접 열어 봐야 하면 --keep-build 를 붙인다.
if (( KEEP_BUILD )); then
  echo "$APP_DIR"
else
  rm -rf "$BUILD_DIR"
  echo "$DMG_PATH"
fi
