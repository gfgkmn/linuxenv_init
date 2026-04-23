#!/usr/bin/env bash
# UserPromptSubmit hook for Claude Code — bridge state tracker.
#
# Fires the instant a user prompt is submitted to CC (user typed +
# Enter, or bridge dispatched). Tells Emacs "session X is now busy"
# so the dashboard can show live busy/idle state without polling.
#
# Same transport pattern as cc-bridge-on-stop.sh — local emacsclient
# fast path, rmate fallback for remote hosts. Never blocks CC.

set -uo pipefail
input=$(cat)

LOG=/tmp/cc-bridge-hook.log
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) $*" >> "$LOG" 2>/dev/null; }

log "prompt-submit: $input"

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$session_id" ]; then
  log "no session_id in payload, exiting"
  exit 0
fi

payload_file=$(mktemp -t "cc-bridge-payload-start.XXXXXX" 2>/dev/null \
               || mktemp "/tmp/cc-bridge-payload-start.XXXXXX")
if [ -z "$payload_file" ]; then
  log "mktemp failed, exiting"
  exit 0
fi
if ! printf '%s' "$input" > "$payload_file" 2>/dev/null; then
  log "write to $payload_file failed, exiting"
  rm -f "$payload_file"
  exit 0
fi

# 1) Local emacsclient — only if the bridge receiver function is bound.
bridge_loaded=0
if command -v emacsclient >/dev/null 2>&1; then
  probe=$(timeout 2s emacsclient --eval \
           '(and (fboundp (quote claude-code-bridge--on-prompt-submit-from-file)) t)' \
           2>/dev/null | tr -d '[:space:]"')
  if [ "$probe" = "t" ]; then
    bridge_loaded=1
  fi
fi

if [ "$bridge_loaded" = "1" ]; then
  log "prompt-submit local emacsclient → $payload_file"
  emacsclient --no-wait --eval \
    "(claude-code-bridge--on-prompt-submit-from-file \"$payload_file\")" \
    >/dev/null 2>&1 || log "emacsclient call failed"
  exit 0
fi

# 2) Remote via rmate (SSH reverse-tunnel).
host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
if command -v rmate >/dev/null 2>&1; then
  log "prompt-submit rmate path: host=$host, payload=$payload_file"
  rmate_out=$(timeout 5s rmate -m "cc-bridge-start||${host}" "$payload_file" 2>&1) \
    || log "rmate exit=$?, out: $rmate_out"
else
  log "no rmate and no local bridge — dropping prompt-submit"
fi

rm -f "$payload_file"
exit 0
