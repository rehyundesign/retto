#!/bin/zsh
# 레토를 손댔을 때 도는 검사. Swift 셀프 테스트와 Claude·Codex 훅 테스트를 함께 돈다.
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
APP_ROOT="${SCRIPT_DIR:h}"

print -- "› Swift 빌드와 자체 검사"
"$APP_ROOT/macos/scripts/build.sh" >/dev/null

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
fi

print -- "통과"
