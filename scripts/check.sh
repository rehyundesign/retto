#!/bin/zsh
# 레토를 손댔을 때 도는 검사. Swift 셀프 테스트와 Claude·Codex 훅 테스트를 함께 돈다.
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
APP_ROOT="${SCRIPT_DIR:h}"

print -- "› Swift 빌드와 자체 검사"
# 검사에서는 배포용 DMG 를 만들지 않는다. 만들면 같은 버전에서 두 번째 검사부터 「이미 있다」로 실패했다.
# 빌드 폴더($TMPDIR/retto-public-*)는 앱 사본을 통째로 담아 macOS 앱 목록에 하나씩 등록된다.
# 통과하면 지우고, 실패하면 원인을 볼 수 있게 남긴다.
build_output=$("$APP_ROOT/macos/scripts/build.sh" --app-only)
build_dir=${${(M)${(f)build_output}:#VERIFIED: *}#VERIFIED: }
if [[ -n "$build_dir" && "$build_dir" == */retto-public-* && -d "$build_dir" ]]; then
  rm -rf -- "$build_dir"
fi

print -- "› 자체 검사 항목이 다 보이는가"
for candidate in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
  [[ -x "$candidate" ]] && NODE_BIN="$candidate" && break
done
if [[ -n "${NODE_BIN:-}" ]]; then
  "$NODE_BIN" "$APP_ROOT/scripts/selftest-flags.mjs" || exit 1
else
  print -- "  node 가 없어 건너뜁니다" >&2
fi

print -- "› 훅 테스트"
for candidate in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
  [[ -x "$candidate" ]] && NODE="$candidate" && break
done
if [[ -z "${NODE:-}" ]]; then
  print -- "  node 가 없어 훅 테스트를 건너뜁니다" >&2
else
  # 실패했을 때만 출력을 보여 준다. 통째로 버리면 커밋 훅이 "실패했습니다" 한 줄만 남겨
  # 무엇이 깨졌는지 알 수가 없다.
  if ! output=$( (cd "$APP_ROOT/hook" && "$NODE" --test tests/*.test.js) 2>&1 ); then
    print -- "$output" >&2
    exit 1
  fi
  # Windows 판의 상태 판정은 맥 앱과 같은 값을 써야 한다. Electron 없이 node 만으로 돈다.
  print -- "› Windows 판 테스트"
  if ! output=$( (cd "$APP_ROOT/windows" && "$NODE" --test test/*.test.js) 2>&1 ); then
    print -- "$output" >&2
    exit 1
  fi
fi

print -- "통과"
