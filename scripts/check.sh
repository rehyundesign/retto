#!/bin/zsh
# 레토를 손댔을 때 도는 검사. 빌드 + 자체 검사 24항목 + 훅 테스트 10개.
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
  (cd "$APP_ROOT/hook" && "$NODE" --test tests/*.test.js >/dev/null)
fi

print -- "통과"
