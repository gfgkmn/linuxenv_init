#!/usr/bin/env bash
# install.sh — wire the Antigravity CLI's hooks to the Emacs bridge.
#
# Writes ~/.gemini/config/hooks.json, the global hook file agy reads,
# with this checkout's hooks/ directory in the commands.  agy wants
# absolute paths and the checkout is under a different home on each
# machine, so the file is written, not linked.
#
# A hooks.json that is already there and differs is left alone: add the
# `cc-bridge' entry this prints to it by hand.  --dry-run only prints.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$HERE/hooks/cc-bridge-hook-agy.sh"
DST="${AGY_CONFIG:-$HOME/.gemini/config}/hooks.json"

case "$HOOK" in *\'*|*\"*|*\\*) echo "cannot quote: $HOOK" >&2; exit 2 ;; esac

new=$(cat <<EOF
{
  "cc-bridge": {
    "PreInvocation": [
      { "type": "command", "command": "bash '$HOOK' prompt-submit", "timeout": 8 }
    ],
    "Stop": [
      { "type": "command", "command": "bash '$HOOK' stop", "timeout": 8 }
    ],
    "PreToolUse": [
      { "matcher": "*", "hooks": [
        { "type": "command", "command": "bash '$HOOK' pretool", "timeout": 8 } ] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [
        { "type": "command", "command": "bash '$HOOK' posttool", "timeout": 8 } ] }
    ]
  }
}
EOF
)

if [ "${1:-}" = "--dry-run" ]; then
  printf 'would write %s:\n%s\n' "$DST" "$new"; exit 0
fi
if [ -e "$DST" ]; then
  if [ "$(cat "$DST")" = "$new" ]; then echo "ok       $DST"; exit 0; fi
  printf '%s exists and differs; add this entry to it by hand:\n%s\n' "$DST" "$new" >&2
  exit 1
fi
mkdir -p "$(dirname "$DST")"
printf '%s\n' "$new" > "$DST"
echo "install  $DST"
