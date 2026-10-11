#!/usr/bin/env bash
# cc-bridge-hook-codex.sh — deliver a Codex hook event to the Emacs bridge.
#
# Events: stop | prompt-submit | pretool | posttool | permission-request
#
# The Claude Code hook (claude-config/hooks/cc-bridge-hook.sh) cannot be
# reused as-is for two reasons:
#
#   * it tags the payload for the Claude path, and the bridge has to know
#     which CLI a session belongs to in order to read its transcript --
#     Codex writes a rollout, Claude writes a jsonl.  So this adds
#     `"agent": "codex"', which is exactly what
#     `claude-code-bridge--agent-of' looks for.
#   * it answers Claude's PreToolUse with `{"permissionDecision":"defer"}'.
#     Codex has a real `PermissionRequest' event, so there is nothing to
#     defer and nothing to print: this script writes NOTHING to stdout
#     ever, which leaves every decision with Codex's own UI.
#
# Emacs is notified, never consulted.  Every call is timeout-bounded so a
# hung or absent Emacs cannot stall a turn, and every failure path exits 0.
#
# Usage in hooks.json:  bash '<path>/cc-bridge-hook-codex.sh' <event>

set -uo pipefail

event="${1:-}"
input=$(cat)
LOG=/tmp/cc-bridge-hook.log
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [codex/$event] $*" >> "$LOG" 2>/dev/null; }
give_up() { log "$1"; exit 0; }

case "$event" in
  stop)               ec_fn=claude-code-bridge--on-stop-from-file ;;
  prompt-submit)      ec_fn=claude-code-bridge--on-prompt-submit-from-file ;;
  pretool)            ec_fn=claude-code-bridge--notify-pretool-from-file ;;
  posttool)           ec_fn=claude-code-bridge--on-posttool-from-file ;;
  permission-request) ec_fn=claude-code-bridge--on-permission-request-from-file ;;
  *) give_up "unknown event" ;;
esac

# Honour the bridge's own kill switches, so one toggle covers both agents.
[ -e "$HOME/.claude/cc-bridge-disabled-globally" ] && exit 0

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session_id" ] && give_up "no session_id"
if [ -f "$HOME/.claude/cc-bridge-disabled-uuids" ] &&
   grep -qxF "$session_id" "$HOME/.claude/cc-bridge-disabled-uuids" 2>/dev/null; then
  exit 0
fi

# Remote Codex has no route yet: the bridge's remote tier is rmate plus a
# Claude-shaped payload.  Say so in the log rather than half-delivering.
if [ -n "${SSH_CONNECTION:-}" ]; then
  give_up "remote Codex session: no transport to the local Emacs yet"
fi

command -v emacsclient >/dev/null 2>&1 || give_up "no emacsclient"
probe=$(timeout 2s emacsclient --eval "(and (fboundp (quote $ec_fn)) t)" 2>/dev/null \
          | tr -d '[:space:]"')
[ "$probe" = "t" ] || give_up "bridge not loaded / emacs unreachable"

# `agent' is what tells the bridge to read a rollout instead of a jsonl.
# jq is already required above; if it were missing we would not be here.
payload=$(mktemp -t "cc-bridge-codex-payload.XXXXXX") || give_up "mktemp"
if ! echo "$input" | jq -c '. + {agent: "codex"}' > "$payload" 2>/dev/null; then
  rm -f "$payload"
  give_up "could not tag payload"
fi

# ITERM_SESSION_ID cascades from the pane through codex into this hook --
# the one place the (session -> iTerm pane) binding is ground truth.
log "fired: ${input:0:200}"
emacsclient --no-wait \
  --eval "($ec_fn \"$payload\" \"${ITERM_SESSION_ID:-}\")" >/dev/null 2>&1 \
  || log "emacsclient call failed"

exit 0
