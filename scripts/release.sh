#!/bin/zsh
# 릴리스 한 번에 — 빌드 → GitHub 릴리스 → Homebrew 탭 갱신.
#
#   scripts/release.sh            # 전부 실행
#   scripts/release.sh --dry-run  # 무엇을 할지만 보여준다
#
# 있는 이유는 하나다 — cask 의 `version` 과 `sha256` 을 손으로 고쳐야 하는데,
# 빼먹으면 사용자가 옛 버전을 받거나 체크섬이 어긋나 설치가 막힌다. 그리고 그걸
# 알아채는 사람은 설치하려던 그 사람뿐이다.
#
# 버전은 macos/scripts/build.sh 의 VERSION 하나가 원천이다. 여기서 읽어 쓴다.
set -euo pipefail
setopt null_glob

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
# gh 는 현재 폴더의 git 원격에서 레포를 알아낸다. 원격 주소를 손으로 파싱하면
# `.git` 이 붙은 경우와 안 붙은 경우가 갈려서, 자리를 옮기고 gh 에게 맡긴다.
cd "$REPO_ROOT"
TAP_REPO="rehyundesign/homebrew-retto"
CASK_PATH="Casks/retto.rb"

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

run() {
  if (( DRY )); then
    print -r -- "  [dry-run] $*"
  else
    "$@"
  fi
}

fail() { print -r -u2 -- "✗ $1"; exit 1 }

VERSION="$(grep '^VERSION=' "$REPO_ROOT/macos/scripts/build.sh" | head -1 | cut -d'"' -f2)"
[[ -n "$VERSION" ]] || fail "build.sh 에서 VERSION 을 읽지 못했습니다."
TAG="v$VERSION"
DMG="$REPO_ROOT/dist/Retto-$VERSION.dmg"

print -r -- "레토 $VERSION 릴리스"
print -r -- ""

# 1. 워킹 트리가 깨끗해야 한다. 커밋하지 않은 변경으로 만든 dmg 를 올리면
#    나중에 그 릴리스를 어떤 소스로 만들었는지 알 수 없다.
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
  fail "커밋하지 않은 변경이 있습니다. 먼저 커밋하거나 되돌려 주세요."
fi

# 2. 같은 태그로 두 번 올리지 않는다. 이미 있으면 버전을 올려야 한다는 뜻이다.
if gh release view "$TAG" >/dev/null 2>&1; then
  fail "$TAG 릴리스가 이미 있습니다. build.sh 의 VERSION 을 올려 주세요."
fi

# 3. 빌드. dmg 와 서명 검사가 여기서 함께 돈다.
print -r -- "› 빌드"
run "$REPO_ROOT/macos/scripts/build.sh"
if (( ! DRY )); then
  [[ -f "$DMG" ]] || fail "dmg 를 찾지 못했습니다 — $DMG"
fi

# 4. 체크섬. cask 가 이 값으로 내려받은 파일을 검사한다.
if (( DRY )); then
  SHA="(빌드 뒤에 계산)"
else
  SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
fi
print -r -- "› sha256  $SHA"

# 5. 릴리스 노트 — 지난 태그 이후의 커밋 제목을 그대로 쓴다.
PREV_TAG="$(git -C "$REPO_ROOT" tag --sort=-v:refname | head -1)"
if [[ -n "$PREV_TAG" ]]; then
  CHANGES="$(git -C "$REPO_ROOT" log --format='- %s' "$PREV_TAG..HEAD")"
else
  CHANGES="$(git -C "$REPO_ROOT" log --format='- %s' -20)"
fi
NOTES="## 깔기

\`\`\`sh
brew tap rehyundesign/retto
brew install --cask retto
\`\`\`

dmg 를 직접 받아 끌어다 놓아도 됩니다. 다만 애플 개발자 서명이 없어서 첫 실행에서
시스템 설정 > 개인정보 보호 및 보안 에서 「그래도 열기」를 한 번 눌러야 합니다.
brew 로 깔거나 직접 빌드하면 그 단계가 없습니다.

## 바뀐 것

$CHANGES"

# 6. GitHub 릴리스.
print -r -- "› GitHub 릴리스 $TAG"
run gh release create "$TAG" "$DMG" --title "Retto $VERSION" --notes "$NOTES"

# 7. 탭. 이 기기에 있으면 그걸 쓰고, 없으면 받아 와서 고치고 되돌려 놓는다 —
#    릴리스하는 기기가 바뀌어도 탭 갱신을 빼먹지 않게.
TAP_DIR="${RETTO_TAP_DIR:-}"
if [[ -z "$TAP_DIR" ]]; then
  for candidate in "${REPO_ROOT:h}/homebrew-retto" "$HOME/Documents/homebrew-retto"; do
    [[ -d "$candidate/.git" ]] && TAP_DIR="$candidate" && break
  done
fi
CLONED=0
if [[ -z "$TAP_DIR" ]]; then
  TAP_DIR="$(mktemp -d)/homebrew-retto"
  print -r -- "› 탭을 받아 옵니다 · $TAP_DIR"
  run gh repo clone "$TAP_REPO" "$TAP_DIR" -- --quiet
  CLONED=1
else
  print -r -- "› 탭 · $TAP_DIR"
  run git -C "$TAP_DIR" pull --quiet --ff-only
fi

print -r -- "› cask 갱신 · version $VERSION · sha256"
if (( ! DRY )); then
  CASK="$TAP_DIR/$CASK_PATH"
  [[ -f "$CASK" ]] || fail "cask 를 찾지 못했습니다 — $CASK"
  # 값이 든 줄만 갈아 끼운다. 주석과 나머지 구조는 그대로 둔다.
  /usr/bin/sed -i '' \
    -e "s/^  version \".*\"$/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" \
    "$CASK"
  grep -q "version \"$VERSION\"" "$CASK" || fail "cask 의 version 을 바꾸지 못했습니다."
  grep -q "sha256 \"$SHA\"" "$CASK" || fail "cask 의 sha256 을 바꾸지 못했습니다."
  ruby -c "$CASK" >/dev/null || fail "cask 문법이 깨졌습니다."

  if [[ -z "$(git -C "$TAP_DIR" status --porcelain)" ]]; then
    print -r -- "  이미 최신입니다"
  else
    git -C "$TAP_DIR" add "$CASK_PATH"
    git -C "$TAP_DIR" commit --quiet -m "레토 $VERSION"
    git -C "$TAP_DIR" push --quiet
    print -r -- "  탭에 올렸습니다"
  fi
fi

(( CLONED && ! DRY )) && rm -rf "${TAP_DIR:h}"

print -r -- ""
print -r -- "✓ 끝. 확인:"
print -r -- "    brew update && brew info --cask retto"
