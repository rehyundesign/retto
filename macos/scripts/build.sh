#!/bin/zsh
# Build the public Mac app from the same versioned runtime and artwork as the release.
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
exec python3 "$SCRIPT_DIR/../../scripts/build-public.py" "$@"
