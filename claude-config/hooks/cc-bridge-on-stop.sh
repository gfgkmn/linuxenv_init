#!/usr/bin/env bash
# Stop hook for Claude Code — unified local/remote.
#
# Transport decision:
#   1. If an Emacs server is reachable AND has `claude-code-bridge--on-stop-from-file'
#      bound, use `emacsclient --eval'. Local fast path.
#   2. Else, if `rmate' is in PATH, emit via the rmate reverse-tunnel with
#      display-name `cc-bridge-stop||<hostname>'. Remote path.
#   3. Else, drop the payload and log.
#
# Never blocks CC with errors; every probe is timeout-guarded.

set -uo pipefail
input=$(cat)

LOG=/tmp/cc-bridge-hook.log
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) $*" >> "$LOG" 2>/dev/null; }

log "fired: $input"

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$session_id" ]; then
  log "no session_id in payload, exiting"
  exit 0
fi

payload_file=$(mktemp -t "cc-bridge-payload.XXXXXX" 2>/dev/null \
               || mktemp "/tmp/cc-bridge-payload.XXXXXX")
if [ -z "$payload_file" ]; then
  log "mktemp failed, exiting"
  exit 0
fi
if ! printf '%s' "$input" > "$payload_file" 2>/dev/null; then
  log "write to $payload_file failed, exiting"
  rm -f "$payload_file"
  exit 0
fi

# 1) Local emacsclient — only if the bridge function is bound on the
# reachable Emacs server. Bare `(boundp 'server-name)' isn't enough
# because a non-bridge Emacs on the same box would pass that check
# and silently eat the event. We probe the specific bridge symbol.
bridge_loaded=0
if command -v emacsclient >/dev/null 2>&1; then
  probe=$(timeout 2s emacsclient --eval \
           '(and (fboundp (quote claude-code-bridge--on-stop-from-file)) t)' \
           2>/dev/null | tr -d '[:space:]"')
  if [ "$probe" = "t" ]; then
    bridge_loaded=1
  fi
fi

if [ "$bridge_loaded" = "1" ]; then
  log "local emacsclient → $payload_file"
  emacsclient --no-wait --eval \
    "(claude-code-bridge--on-stop-from-file \"$payload_file\")" \
    >/dev/null 2>&1 || log "emacsclient call failed"
  # Emacs deletes the file after reading.
  exit 0
fi

# 2) Remote via rmate (SSH reverse-tunnel).
host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
if command -v rmate >/dev/null 2>&1; then
  log "rmate path: host=$host, payload=$payload_file"
  rmate_out=$(timeout 5s rmate -m "cc-bridge-stop||${host}" "$payload_file" 2>&1) \
    || log "rmate exit=$?, out: $rmate_out"
else
  log "no rmate and no local bridge — dropping payload"
fi

rm -f "$payload_file"
exit 0
