#!/bin/bash
# Stop hook: a substantial reply must end with the status block.
#
#   **Status: <done | needs you | running | blocked>**
#   - You: ...
#   - Running: ...
#   - Not done: ...
#
# Two checks, each sends the reply back to Claude at most once:
#   1. The block is missing from a reply of STATUS_MIN_CHARS or more.
#   2. Claude Code reports background work, but the block says nothing runs.
# Check 2 uses the harness's own task list, so it does not rely on the model
# remembering what it started.
#
# Short answers are exempt. The hook never blocks twice in a row.

set -uo pipefail

INPUT=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<< "$INPUT" 2>/dev/null)" = "true" ] && exit 0

MSG=$(jq -r '.last_assistant_message // empty' <<< "$INPUT" 2>/dev/null)
[ -n "$MSG" ] || exit 0

MIN="${STATUS_MIN_CHARS:-600}"
BG=$(jq -r '[(.background_tasks // [])[], (.session_crons // [])[]] | length' <<< "$INPUT" 2>/dev/null)
case "$BG" in ''|*[!0-9]*) BG=0 ;; esac

block() {
  jq -cn --arg reason "$1" '{decision: "block", reason: $reason}'
  exit 0
}

FORMAT='**Status: <done | needs you | running | blocked>** followed by three lines: "- You: ...", "- Running: ...", "- Not done: ...".'

STATUS=$(printf '%s\n' "$MSG" \
  | grep -oE '^\*\*Status: (done|needs you|running|blocked)\*\*[[:space:]]*$' \
  | tail -n 1 | sed -E 's/^\*\*Status: //; s/\*\*[[:space:]]*$//')

if [ -z "$STATUS" ]; then
  [ "${#MSG}" -ge "$MIN" ] || exit 0
  block "Your reply has no status block. End it with $FORMAT"
fi

if [ "$BG" -gt 0 ]; then
  RUNNING=$(printf '%s\n' "$MSG" | grep -iE '^- Running:' | tail -n 1)
  WHAT=$(jq -r '[(.background_tasks // [])[] | (.description // .command // .type // "task")] | .[0:3] | join("; ")' <<< "$INPUT" 2>/dev/null | cut -c1-200)
  if [ "$STATUS" = "done" ] || [ -z "$RUNNING" ] || printf '%s' "$RUNNING" | grep -qiE 'nothing|none'; then
    block "Claude Code reports $BG background task(s) still in flight (${WHAT:-no description}). The status block must say so on the Running line, and the status cannot be done."
  fi
fi

exit 0
