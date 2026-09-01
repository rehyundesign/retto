#!/bin/sh
# 훅을 돌릴 node 를 찾아서 hook.cjs 에 넘긴다.
#
# 예전에는 settings.json 에 node 절대경로를 직접 넣었다. GUI 로 띄운 Claude Code 는
# PATH 가 거의 비어 있어서 그래야 했는데, nvm·fnm·volta 로 node 버전을 바꾸면
# 그 경로가 사라져 훅 열일곱 개가 한꺼번에 동작을 멈췄다. 사용자에게는 아무 표시도
# 남지 않고 레토만 계속 자고 있었다.
#
# 그래서 경로를 한 곳에 고정하지 않고 여기서 차례로 확인한다. 설치할 때 고른 자리를
# 먼저 보고, 없으면 흔한 자리와 버전 관리자 자리를 본다.
#
# 표준 입력(훅 이벤트 JSON)은 exec 로 그대로 넘어간다.

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PINNED='__RETTO_NODE__'
NODE=''

pick() {
  [ -z "$NODE" ] && [ -n "$1" ] && [ -x "$1" ] && NODE="$1"
}

pick "$PINNED"
pick /opt/homebrew/bin/node
pick /usr/local/bin/node
pick /usr/bin/node
pick "$(command -v node 2>/dev/null)"

# 버전 관리자로 깐 node. 여러 개면 이름 순으로 마지막 것(대개 최신)을 쓴다.
if [ -z "$NODE" ]; then
  for candidate in \
    "$HOME"/.volta/bin/node \
    "$HOME"/.fnm/aliases/default/bin/node \
    "$HOME"/Library/Application\ Support/fnm/aliases/default/bin/node \
    "$HOME"/.local/share/fnm/aliases/default/bin/node \
    "$HOME"/.nvm/versions/node/*/bin/node \
    "$HOME"/Library/pnpm/node \
    "$HOME"/.asdf/shims/node
  do
    [ -x "$candidate" ] && NODE="$candidate"
  done
fi

# node 가 하나도 없으면 아무것도 하지 않고 끝낸다. 훅이 실패하면 Claude Code 가
# 오류를 띄우는데, 레토 때문에 남의 작업에 경고가 붙는 것은 과하다.
[ -n "$NODE" ] || exit 0

exec "$NODE" "$DIR/hook.cjs" "$@"
