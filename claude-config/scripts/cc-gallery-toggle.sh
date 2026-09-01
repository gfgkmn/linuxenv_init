#!/bin/bash
# cc-gallery-toggle.sh — arm or disarm unattended screenshot galleries.
#
# Off (default): the agent asks before capturing a batch and before publishing.
# On:            it may build, capture and publish a gallery without asking —
#                meant for the hours you are asleep or away from the desk.
#
# State is the presence of the flag file, matching the cc-bridge convention.
# cc-gallery.py --auto refuses to run while the file is absent, so this is the
# switch, not a suggestion.
#
# Usage: cc-gallery-toggle.sh [on|off|status]

set -euo pipefail

FLAG="${CC_GALLERY_FLAG:-$HOME/.claude/gallery-enabled}"

status() {
  if [ -e "$FLAG" ]; then
    echo "gallery: FULL AUTO — unattended capture and publish allowed"
    echo "  flag: $FLAG (since $(stat -f '%Sm' "$FLAG"))"
  else
    echo "gallery: SEMI AUTO — the agent asks before capturing and publishing"
    echo "  flag: $FLAG (absent)"
  fi
}

case "${1:-toggle}" in
  on)     : > "$FLAG"; status ;;
  off)    rm -f "$FLAG"; status ;;
  status) status ;;
  toggle) if [ -e "$FLAG" ]; then rm -f "$FLAG"; else : > "$FLAG"; fi; status ;;
  *)      echo "usage: $(basename "$0") [on|off|status|toggle]" >&2; exit 1 ;;
esac
