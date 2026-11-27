#!/usr/bin/env bash
# install.sh — load the Emacs bridge's extension in every Pi session.
#
# Links extensions/cc-bridge.ts into ~/.pi/agent/extensions/, where Pi
# finds global extensions.  A file that is already there and is not this
# link is left alone.  --dry-run only prints.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC="$HERE/extensions/cc-bridge.ts"
DST="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions/cc-bridge.ts"

if [ "${1:-}" = "--dry-run" ]; then
  printf 'would link %s -> %s\n' "$DST" "$SRC"; exit 0
fi
if [ -L "$DST" ] && [ "$(readlink "$DST")" = "$SRC" ]; then
  echo "ok       $DST"; exit 0
fi
if [ -e "$DST" ] || [ -L "$DST" ]; then
  echo "$DST exists and is not this link; left alone" >&2; exit 1
fi
mkdir -p "$(dirname "$DST")"
ln -s "$SRC" "$DST"
echo "install  $DST"
