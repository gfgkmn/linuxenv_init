#!/usr/bin/env bash
# Stop hook for Claude Code — works on both macOS (local) and Linux
# (remote, via rmate reverse-tunnel).
#
# Transports, tried in order:
#   1. emacsclient --eval → claude-code-bridge--on-stop-from-file
#      (local path: fast, no network).
#   2. rmate with `cc-bridge-stop||<hostname>` display-name marker.
#      rmate reaches the user's local Emacs over the SSH reverse
#      tunnel (RemoteForward 52698 → 127.0.0.1:52698). Emacs'
#      rmate-server sees the marker and routes to the bridge handler
#      instead of opening an editor buffer.
#
# Silent no-op if neither transport is available — never blocks CC.

set -uo pipefail
input=$(cat)

# DEBUG: log every fire so we can see what CC sent.
LOG=/tmp/cc-bridge-hook.log
echo "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) fired: $input" >> "$LOG" 2>/dev/null

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session_id" ] && exit 0

# Write the full payload (session_id, transcript_path, cwd, and
# crucially `last_assistant_message`) to a temp file. Avoids
# shell-quoting multiline/backticked/quoted response text.
payload_file=$(mktemp -t "cc-bridge-payload.XXXXXX" 2>/dev/null \
               || mktemp "/tmp/cc-bridge-payload.XXXXXX")
[ -z "$payload_file" ] && exit 0
printf '%s' "$input" > "$payload_file" 2>/dev/null || {
  rm -f "$payload_file"
  exit 0
}

# 1) Local emacsclient (fastest, no network).
if command -v emacsclient >/dev/null 2>&1 \
   && emacsclient --no-wait --eval '(and (boundp (quote server-name)) t)' \
                  >/dev/null 2>&1; then
  emacsclient --no-wait --eval \
    "(when (fboundp 'claude-code-bridge--on-stop-from-file) (claude-code-bridge--on-stop-from-file \"$payload_file\"))" \
    >/dev/null 2>&1 || true
  # Emacs deletes the file after reading; no explicit rm here.
  exit 0
fi

# 2) Remote: rmate via SSH reverse tunnel.
host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
if command -v rmate >/dev/null 2>&1; then
  # timeout guards against a missing reverse tunnel hanging CC.
  # Client blocks until server sends `close`; bridge handler does
  # that synchronously after popping the result buffer.
  timeout 5s rmate -m "cc-bridge-stop||${host}" "$payload_file" \
    >/dev/null 2>&1 || true
fi

rm -f "$payload_file"
exit 0
