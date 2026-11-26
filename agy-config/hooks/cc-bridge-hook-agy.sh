#!/usr/bin/env bash
# cc-bridge-hook-agy.sh — deliver an Antigravity CLI hook event to the
# Emacs bridge.
#
# Events: prompt-submit | stop | pretool | posttool
#
#   prompt-submit   wired to agy's PreInvocation.  agy has no hook for a
#                   submitted prompt; PreInvocation runs before every
#                   model call, and the first of a turn (invocationNum 0)
#                   is the prompt.  The later ones are dropped here.
#   stop            wired to agy's Stop.
#
#   pretool         wired to agy's PreToolUse.  agy has no hook for "I am
#                   asking the user"; the bridge looks at the session's
#                   screen after this event to find out.
#   posttool        wired to agy's PostToolUse: the tool ran.
#
# PreToolUse is the one hook whose stdout agy takes as a DECISION, and an
# answer with no decision denies the tool.  So `pretool' prints
# `{"decision":"allow"}' -- on every path, also when Emacs is away or the
# bridge is switched off.  `allow' means "no objection": with
# `toolPermission' strict agy still asked the user (measured, 1.5.17).
# It is not `auto_approve'.
#
# The payload goes to Emacs as agy sent it plus `"agent": "agy"'; the
# bridge's agy module translates the field names.
#
# agy reads this script's stdout as JSON, so it prints one JSON object
# and nothing else, on every path.  Emacs is notified, never consulted; every call is
# timeout-bounded and every failure path exits 0.
#
# Usage in ~/.gemini/config/hooks.json:
#   bash '<path>/cc-bridge-hook-agy.sh' <event>

set -uo pipefail

event="${1:-}"
input=$(cat)
LOG=/tmp/cc-bridge-hook.log
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [agy/$event] $*" >> "$LOG" 2>/dev/null; }
finish() {
  if [ "$event" = pretool ]; then echo '{"decision":"allow"}'; else echo '{}'; fi
  exit 0
}
give_up() { log "$1"; finish; }

case "$event" in
  stop)          ec_fn=claude-code-bridge--on-stop-from-file ;;
  prompt-submit) ec_fn=claude-code-bridge--on-prompt-submit-from-file ;;
  pretool)       ec_fn=claude-code-bridge--notify-pretool-from-file ;;
  posttool)      ec_fn=claude-code-bridge--on-posttool-from-file ;;
  *) give_up "unknown event" ;;
esac

# Honour the bridge's own kill switches, so one toggle covers every agent.
[ -e "$HOME/.claude/cc-bridge-disabled-globally" ] && finish

command -v jq >/dev/null 2>&1 || give_up "no jq"
session_id=$(echo "$input" | jq -r '.conversationId // empty' 2>/dev/null)
[ -z "$session_id" ] && give_up "no conversationId"
if [ -f "$HOME/.claude/cc-bridge-disabled-uuids" ] &&
   grep -qxF "$session_id" "$HOME/.claude/cc-bridge-disabled-uuids" 2>/dev/null; then
  finish
fi

if [ "$event" = prompt-submit ]; then
  n=$(echo "$input" | jq -r '.invocationNum // 0' 2>/dev/null)
  [ "$n" = "0" ] || finish
fi

if [ -n "${SSH_CONNECTION:-}" ]; then
  give_up "remote agy session: no transport to the local Emacs yet"
fi

command -v emacsclient >/dev/null 2>&1 || give_up "no emacsclient"
probe=$(timeout 2s emacsclient --eval "(and (fboundp (quote $ec_fn)) t)" 2>/dev/null \
          | tr -d '[:space:]"')
[ "$probe" = "t" ] || give_up "bridge not loaded / emacs unreachable"

payload=$(mktemp -t "cc-bridge-agy-payload.XXXXXX") || give_up "mktemp"
if ! echo "$input" | jq -c '. + {agent: "agy"}' > "$payload" 2>/dev/null; then
  rm -f "$payload"
  give_up "could not tag payload"
fi

log "fired: ${input:0:200}"
emacsclient --no-wait \
  --eval "($ec_fn \"$payload\" \"${ITERM_SESSION_ID:-}\")" >/dev/null 2>&1 \
  || log "emacsclient call failed"

finish
