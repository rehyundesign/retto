#!/bin/zsh
# 레토 훅을 설치·갱신한다. --uninstall 로 제거.
# GUI 앱에서도 부를 수 있게 node 를 흔한 자리에서 직접 찾는다.
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
HOOK_DIR="${SCRIPT_DIR:h}/hook"

for candidate in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node "$(command -v node 2>/dev/null || true)"; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    NODE="$candidate"
    break
  fi
done

if [[ -z "${NODE:-}" ]]; then
  echo "node 를 찾지 못했습니다. Node.js 를 설치해 주세요." >&2
  exit 1
fi

exec "$NODE" "$HOOK_DIR/install.cjs" "$@"
