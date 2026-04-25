#!/usr/bin/env bash
# cc-bridge-hook.sh — unified Claude Code hook dispatcher for the bridge.
#
# Replaces the previous four scripts (cc-bridge-on-{stop,prompt-submit,notify}.sh
# and cc-bridge-pretool.sh) which were 90% duplicate boilerplate.
#
# Usage in settings.json:
#   "command": "bash ~/.claude/hooks/cc-bridge-hook.sh <event>"
# Where <event> is: stop | prompt-submit | notify | pretool
#
# Transport rules:
#   * Local box (no $SSH_CONNECTION):   try emacsclient.  If the bridge isn't
#                                       loaded or Emacs is hung, log + exit.
#                                       Never falls back to rmate locally.
#   * Remote SSH session ($SSH_CONNECTION set):  rmate reverse-tunnel back to
#                                                the local Emacs.
#   * `pretool' blocks for the user's decision and ALWAYS prints a JSON
#     response on stdout (defaults to "defer" on failure so CC's TUI handles
#     the prompt natively).  The other three are fire-and-forget.
#
# Every probe and rmate ping is timeout-bounded so a hung Emacs / dead
# ControlMaster cannot stall CC.

set -uo pipefail

event="${1:-}"
input=$(cat)
LOG=/tmp/cc-bridge-hook.log
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) [$event] $*" >> "$LOG" 2>/dev/null; }

# Per-event lookup: elisp function | rmate display-name prefix | blocking?
case "$event" in
  stop)
    ec_fn=claude-code-bridge--on-stop-from-file
    rmate_prefix=cc-bridge-stop
    blocking=0 ;;
  prompt-submit)
    ec_fn=claude-code-bridge--on-prompt-submit-from-file
    rmate_prefix=cc-bridge-start
    blocking=0 ;;
  notify)
    ec_fn=claude-code-bridge--on-notification-from-file
    rmate_prefix=cc-bridge-notify
    blocking=0 ;;
  pretool)
    ec_fn=claude-code-bridge--await-decision-from-file
    rmate_prefix=cc-bridge-pretool
    blocking=1 ;;
  *)
    log "unknown event: $event"
    exit 0 ;;
esac

# PreToolUse must always emit SOMETHING to stdout, or CC hangs forever.
emit_defer() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}'
  exit 0
}
fail() {
  log "$1"
  [ "$blocking" = "1" ] && emit_defer
  exit 0
}

log "fired: ${input:0:200}"

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session_id" ] && fail "no session_id"

# ── Tier 1: local emacsclient — only on the local box, no rmate fallback ──
if [ -z "${SSH_CONNECTION:-}" ]; then
  command -v emacsclient >/dev/null 2>&1 || fail "no emacsclient"
  probe=$(timeout 2s emacsclient --eval "(and (fboundp (quote $ec_fn)) t)" 2>/dev/null \
            | tr -d '[:space:]"')
  [ "$probe" = "t" ] || fail "bridge not loaded / emacs unreachable"

  if [ "$blocking" = "1" ]; then
    # PreToolUse: REQ + RESP file handshake, async.  Emacs's
    # `--await-decision-from-file' opens the delegate buffer and returns
    # immediately — no `recursive-edit', main thread stays responsive
    # while the user reviews the decision.  We poll RESP for the JSON
    # the user's action key writes (same shape as the remote rmate path
    # below).
    req=$(mktemp -t "cc-bridge-req.XXXXXX") || fail "mktemp req"
    resp=$(mktemp -t "cc-bridge-resp.XXXXXX") || { rm -f "$req"; fail "mktemp resp"; }
    rm -f "$resp"  # emacs creates it when an action key fires
    printf '%s' "$input" > "$req" || { rm -f "$req"; fail "write req"; }
    log "local async open → $req / $resp"
    emacsclient --no-wait --eval "($ec_fn \"$req\" \"$resp\")" >/dev/null 2>&1 \
      || { rm -f "$req"; fail "emacsclient open failed"; }
    log "local polling $resp"
    while [ ! -s "$resp" ]; do sleep 0.5; done
    cat "$resp"
    rm -f "$req" "$resp"
    exit 0
  fi

  # Fire-and-forget: stash payload, --no-wait emacsclient.  Emacs deletes
  # the payload file after reading.
  payload=$(mktemp -t "cc-bridge-payload.XXXXXX") || fail "mktemp payload"
  printf '%s' "$input" > "$payload" || { rm -f "$payload"; fail "write payload"; }
  log "local emacsclient → $payload"
  emacsclient --no-wait --eval "($ec_fn \"$payload\")" >/dev/null 2>&1 \
    || log "emacsclient call failed"
  exit 0
fi

# ── Tier 2: remote — rmate reverse-tunnel to the local Emacs ─────────────
command -v rmate >/dev/null 2>&1 || fail "no rmate on remote"
host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
display_name="${rmate_prefix}||${host}"

if [ "$blocking" = "1" ]; then
  # Stable REQ path under cc-state so Emacs reaches it via TRAMP using the
  # exact filename we chose.  Unique per request so concurrent decisions
  # don't stomp on each other.
  mkdir -p "$HOME/.claude/cc-state" 2>/dev/null
  req_id="${session_id}-$$"
  req_remote="$HOME/.claude/cc-state/pretool-req-${req_id}.json"
  resp_remote="$HOME/.claude/cc-state/pretool-resp-${req_id}.json"
  printf '%s' "$input" > "$req_remote" || fail "remote write req"
  rm -f "$resp_remote"
  log "remote rmate ping → $display_name  req=$req_remote"
  printf '%s\n' "$req_remote" \
    | timeout 5s rmate -m "$display_name" - >>"$LOG" 2>&1 \
    || { rm -f "$req_remote"; fail "rmate ping failed"; }
  # Poll for RESP (no inotify on remote-mounted paths, and a human is
  # reviewing on the other end — minutes are valid).  0.5s is invisible.
  log "remote polling $resp_remote"
  while [ ! -s "$resp_remote" ]; do sleep 0.5; done
  cat "$resp_remote"
  rm -f "$req_remote" "$resp_remote"
  exit 0
fi

# Remote fire-and-forget
payload=$(mktemp -t "cc-bridge-payload.XXXXXX") || fail "mktemp payload"
printf '%s' "$input" > "$payload" || { rm -f "$payload"; fail "write payload"; }
log "remote rmate → $display_name  payload=$payload"
timeout 5s rmate -m "$display_name" "$payload" 2>>"$LOG" \
  || log "rmate exit=$?"
rm -f "$payload"
exit 0
