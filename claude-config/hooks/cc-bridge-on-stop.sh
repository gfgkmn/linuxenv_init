#!/usr/bin/env bash
# Stop hook: forward the full CC Stop payload (which includes
# `last_assistant_message` in this CC build) to Emacs via a temp
# file. Emacs parses it and pops the dispatch result buffer.
# Silent no-op if emacsclient is unavailable or no Emacs server is
# running — never blocks the main CC flow.
set -uo pipefail
input=$(cat)

# DEBUG: log every fire so we can see what CC sent.
echo "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) fired: $input" >> /tmp/cc-bridge-hook.log

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session_id" ] && exit 0

# Write the full payload (session_id, transcript_path, and crucially
# `last_assistant_message`) to a per-session temp file. Avoids
# shell-quoting multiline/backticked/quoted response text through
# emacsclient --eval. Emacs deletes the file after reading.
payload_file="/tmp/cc-bridge-payload-${session_id}-$(date +%s%N).json"
printf '%s' "$input" > "$payload_file" 2>/dev/null || exit 0

if command -v emacsclient >/dev/null 2>&1; then
  emacsclient --no-wait --eval \
    "(when (fboundp 'claude-code-bridge--on-stop-from-file) (claude-code-bridge--on-stop-from-file \"$payload_file\"))" \
    >/dev/null 2>&1 || true
fi
exit 0
