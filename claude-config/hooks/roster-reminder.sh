#!/bin/bash
# UserPromptSubmit hook: remind gfgkmn to test a model that the roster has
# not recorded.
#
# Fires only when BOTH hold:
#   - this session has passed TURN_LIMIT user turns, and
#   - the model now running does not appear in the roster file.
# It then stays quiet: one reminder per model per day, across all sessions.
#
# The reminder is a `systemMessage`, shown to the user only. It adds nothing
# to the model's context. The hook never blocks a prompt.
#
# Settings: ROSTER_FILE, ROSTER_TURN_LIMIT, ROSTER_STATE_DIR (all optional).

set -uo pipefail

ROSTER="${ROSTER_FILE:-$HOME/.claude/agent-rules/roster.md}"
TURN_LIMIT="${ROSTER_TURN_LIMIT:-20}"
STATE_DIR="${ROSTER_STATE_DIR:-$HOME/.claude/state/roster-reminder}"

INPUT=$(cat)
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$SESSION" ] || exit 0
[ -f "$ROSTER" ] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Count this session's user turns. A counter file keeps the hook cheap: it
# never has to read the whole transcript.
COUNT_FILE="$STATE_DIR/$SESSION.turns"
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

[ "$COUNT" -gt "$TURN_LIMIT" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0

# The model that answered most recently in the main conversation.
MODEL=$(tail -n 400 "$TRANSCRIPT" \
  | jq -rR 'fromjson? | select(.type == "assistant" and (.isSidechain | not)) | .message.model // empty' 2>/dev/null \
  | grep -v '^<' | tail -n 1)
[ -n "$MODEL" ] || exit 0

# Recorded in the roster: nothing to say.
if grep -qF -- "$MODEL" "$ROSTER"; then
  exit 0
fi

# Already reminded about this model today.
MARK="$STATE_DIR/reminded.$(printf '%s' "$MODEL" | tr -c 'A-Za-z0-9._-' '_').$(date +%Y-%m-%d)"
[ -e "$MARK" ] && exit 0
: > "$MARK"

jq -cn --arg m "$MODEL" --arg r "$ROSTER" --arg n "$TURN_LIMIT" \
  '{systemMessage: ("Roster reminder: this session has passed " + $n + " turns on " + $m + ", which the roster has not recorded. When you have a moment, run your test tasks and add the model id and date to " + $r + ".")}'
exit 0
