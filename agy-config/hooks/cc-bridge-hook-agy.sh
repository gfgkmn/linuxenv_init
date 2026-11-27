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
# PreToolUse is the one hook whose stdout agy takes as a DECISION, so
# `pretool' prints NOTHING, on every path, also when Emacs is away or
# the bridge is switched off.  Measured on agy 1.5.17 (2026-11-27), one
# `run_command' per case, against a run with no PreToolUse hook at all:
#
#   hook prints             default mode        toolPermission strict
#   (no hook)               tool runs           agy asks the user
#   nothing                 tool runs           agy asks the user
#   {"decision":"allow"}    tool runs           agy asks the user
#   {}                      DENIED by the hook  DENIED by the hook
#
# Nothing and `allow' came out the same in both; nothing is the one that
# is no opinion by construction, where `allow' is one that happened to
# change nothing here (not measured: a deny or ask rule in agy's own
# settings).  Orca's hook does the same (stablyai/orca, hook-events.ts).
#
# The payload goes to Emacs as agy sent it plus `"agent": "agy"'; the
# bridge's agy module translates the field names.
#
# For every other event agy reads this script's stdout as JSON, so it
# prints one JSON object and nothing else.  Emacs is notified, never
# consulted; every call is timeout-bounded and every failure path exits 0.
#
# Usage in ~/.gemini/config/hooks.json:
#   bash '<path>/cc-bridge-hook-agy.sh' <event>

set -uo pipefail

event="${1:-}"
input=$(cat)
LOG=/tmp/cc-bridge-hook.log
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [agy/$event] $*" >> "$LOG" 2>/dev/null; }
finish() {
  [ "$event" = pretool ] || echo '{}'
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

# CC_BRIDGE_LOCAL: a session the bridge started here reports here,
# whatever SSH_CONNECTION says (see cc-bridge-hook.sh).
if [ -n "${SSH_CONNECTION:-}" ] && [ -z "${CC_BRIDGE_LOCAL:-}" ]; then
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
