#!/usr/bin/env bash
# cc-bridge-hook.sh — unified Claude Code hook dispatcher for the bridge.
#
# Events: stop | stop-failure | prompt-submit | notify | pretool | posttool
#
# All events are fire-and-forget except two:
#   * `pretool' still emits a JSON `defer' to stdout, so CC's TUI
#     handles the permission decision.
#   * `permreq', on the local box and with an Emacs that knows how,
#     WAITS for Emacs's answer and prints it as the decision (see
#     "PermissionRequest: wait for Emacs" below).  The dialog in CC's
#     TUI stays usable all the while; whichever answers first wins.
#
# Transport rules:
#   * Local box (no $SSH_CONNECTION):   try emacsclient.  If the bridge
#                                       isn't loaded or Emacs is hung,
#                                       log + exit silently.
#   * Remote SSH session ($SSH_CONNECTION set):  rmate reverse-tunnel
#                                                back to the local Emacs.
#
# Every probe and rmate ping is timeout-bounded so a hung Emacs / dead
# ControlMaster cannot stall CC.

set -uo pipefail

event="${1:-}"
input=$(cat)
LOG=/tmp/cc-bridge-hook.log
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ) [$event] $*" >> "$LOG" 2>/dev/null; }

emit_defer() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}'
}

# ── Per-session hook disable ─────────────────────────────────────────
# Emacs maintains ~/.claude/cc-bridge-disabled-uuids — newline-delimited
# UUIDs flagged by `M-x claude-code-bridge-toggle-session-hooks'.  When
# the incoming payload's session_id is in that set, short-circuit:
#   * stop / prompt-submit / notify / posttool → exit 0 silently.
#   * pretool                                  → emit `defer' so CC's
#                                                TUI handles the prompt.
# ── Global kill switch ───────────────────────────────────────────────
# Single file presence test: when present, EVERY hook event (across
# every session) short-circuits.  Coarser than the per-session
# disable below — used by `M-x claude-code-bridge-toggle-bridge-globally'
# (Emacs side) or `cc-bridge-toggle-globally' (CLI / slash command)
# to silence the bridge entirely without per-session bookkeeping.
GLOBAL_DISABLE_FILE="${HOME}/.claude/cc-bridge-disabled-globally"
if [[ -e "$GLOBAL_DISABLE_FILE" ]]; then
  log "GLOBAL DISABLE active — short-circuit (event=$event)"
  [[ "$event" == "pretool" ]] && emit_defer
  exit 0
fi

DISABLE_FILE="${HOME}/.claude/cc-bridge-disabled-uuids"
if [[ -r "$DISABLE_FILE" ]]; then
  payload_uuid="$(printf %s "$input" \
                  | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]+"' \
                  | head -n1 \
                  | sed -E 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  if [[ -n "$payload_uuid" ]] \
     && grep -Fxq "$payload_uuid" "$DISABLE_FILE" 2>/dev/null; then
    log "DISABLED for uuid=${payload_uuid:0:8} — short-circuit"
    [[ "$event" == "pretool" ]] && emit_defer
    exit 0
  fi
fi

# ── Pretool: best-effort allow-rule filter ───────────────────────────
# Replicates CC's `permissions.allow' matching for the common shapes:
#   * Bare name (e.g. `Read', `Write')      → matches the tool wholesale.
#   * Bash(<glob>)                          → fnmatch each shell piece
#                                             after splitting on
#                                             `;'/`&&'/`||'/`|' and
#                                             stripping redirections.
#   * WebFetch(domain:<host>)               → URL host equals or is a
#                                             subdomain of <host>.
#   * Read(<path-glob>) / similar           → fnmatch the matched arg.
#
# When ALL parts of the call match an allow pattern, the bridge stays
# silent — CC's permission system handles it natively.  Otherwise we
# fire-and-forget a notify to Emacs and emit `defer' so CC's TUI is
# the sole decision point.  Edge cases (command substitutions,
# heredocs) leak through as false-positive notifications, never as
# wrong decisions.
if [[ "$event" == "pretool" ]]; then
  pretool_settings_file="$HOME/.claude/settings.json"
  if [[ -r "$pretool_settings_file" ]]; then
    pretool_decision="$(CC_BRIDGE_SETTINGS_FILE="$pretool_settings_file" \
      printf %s "$input" | CC_BRIDGE_SETTINGS_FILE="$pretool_settings_file" \
      python3 -c '
import sys, json, os, re, fnmatch
from urllib.parse import urlparse

def split_shell(cmd):
    # Bash treats a bare newline as a command separator (equivalent to ;).
    # Include it in the alternation so multi-line commands split into pieces.
    pieces = re.split(r"\s*(?:;|&&|\|\||\||\n)\s*", cmd)
    return [p.strip() for p in pieces if p.strip()]

def strip_redirs(piece):
    piece = re.sub(r"\s+\d?>>?\s*\S+", "", piece)
    piece = re.sub(r"\s+\d?<\s*\S+", "", piece)
    piece = re.sub(r"\s+&>\s*\S+", "", piece)
    piece = re.sub(r"\s+\d?>&\d", "", piece)
    return piece.strip()

def bash_piece_allowed(piece, bash_globs):
    piece = strip_redirs(piece)
    if not piece:
        return True
    for g in bash_globs:
        if fnmatch.fnmatchcase(piece, g):
            return True
    return False

def webfetch_allowed(url, domain_patterns):
    try:
        host = urlparse(url).hostname or ""
    except Exception:
        return False
    if not host:
        return False
    host = host.lower()
    for pat in domain_patterns:
        pat = pat.lower().strip()
        if host == pat or host.endswith("." + pat):
            return True
    return False

try:
    d = json.load(sys.stdin)
    tool = d.get("tool_name") or ""
    tinput = d.get("tool_input") or {}
    settings_path = os.environ.get("CC_BRIDGE_SETTINGS_FILE")
    s = json.load(open(settings_path))
    allow = s.get("permissions", {}).get("allow", []) or []

    bare = set()
    by_tool = {}
    for entry in allow:
        m = re.match(r"^([A-Za-z][A-Za-z0-9_]*)\((.*)\)$", entry)
        if m:
            t, arg = m.group(1), m.group(2)
            by_tool.setdefault(t, []).append(arg)
        else:
            bare.add(entry.strip())

    if tool in bare:
        print("allowed"); sys.exit(0)

    if tool == "Bash":
        cmd = tinput.get("command") or ""
        bash_globs = by_tool.get("Bash", [])
        if cmd and bash_globs:
            pieces = split_shell(cmd)
            if pieces and all(bash_piece_allowed(p, bash_globs) for p in pieces):
                print("allowed"); sys.exit(0)
    elif tool == "WebFetch":
        url = tinput.get("url") or ""
        wf = by_tool.get("WebFetch", [])
        domains = [a[len("domain:"):] for a in wf if a.startswith("domain:")]
        if url and domains and webfetch_allowed(url, domains):
            print("allowed"); sys.exit(0)
    elif tool in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = (tinput.get("file_path") or tinput.get("notebook_path") or "")
        globs = by_tool.get(tool, [])
        if path and globs:
            for g in globs:
                if fnmatch.fnmatchcase(path, g):
                    print("allowed"); sys.exit(0)
except Exception:
    pass
' 2>/dev/null)"
    if [[ "$pretool_decision" == "allowed" ]]; then
      log "PRETOOL allowed by permissions.allow filter — silent"
      exit 0
    fi
  fi
fi

# Per-event lookup: elisp function | rmate display-name prefix.
case "$event" in
  stop)
    ec_fn=claude-code-bridge--on-stop-from-file
    rmate_prefix=cc-bridge-stop ;;
  stop-failure)
    # StopFailure: fires INSTEAD of Stop when an API error (lost
    # connection, rate limit, auth) ended the turn.  Without it Emacs
    # never learns the turn is over.
    ec_fn=claude-code-bridge--on-stop-failure-from-file
    rmate_prefix=cc-bridge-stopfail ;;
  prompt-submit)
    ec_fn=claude-code-bridge--on-prompt-submit-from-file
    rmate_prefix=cc-bridge-start ;;
  notify)
    ec_fn=claude-code-bridge--on-notification-from-file
    rmate_prefix=cc-bridge-notify ;;
  pretool)
    ec_fn=claude-code-bridge--notify-pretool-from-file
    rmate_prefix=cc-bridge-pretool ;;
  posttool)
    ec_fn=claude-code-bridge--on-posttool-from-file
    rmate_prefix=cc-bridge-posttool ;;
  permreq)
    # PermissionRequest: fires only when CC actually needs a decision and
    # carries tool_name/tool_input.  Stdout here is read as a decision, so
    # we print NOTHING unless Emacs gave one (hold_for_answer).
    ec_fn=claude-code-bridge--on-permission-request-from-file
    rmate_prefix=cc-bridge-permreq ;;
  *)
    log "unknown event: $event"
    [[ "$event" == "pretool" ]] && emit_defer
    exit 0 ;;
esac

# Fire-and-forget IPC; pretool also emits `defer' to stdout afterwards
# so CC's TUI is the sole decision point.
fail() {
  log "$1"
  [[ "$event" == "pretool" ]] && emit_defer
  exit 0
}

# ── PermissionRequest: wait for Emacs ────────────────────────────────
# CC runs this hook while its permission dialog is up and takes a
# decision the hook prints.  So instead of typing keys into the TUI,
# Emacs answers here: we make a directory, leave our pid in it, tell
# Emacs (claude-code-bridge-request.el), and wait for the file `answer':
#
#   allow          this once
#   allow-always   and write the rule CC suggested (the dialog's
#                  "Yes, and don't ask again ...")
#   deny           and stop, as the dialog's "No" does
#   (empty)        Emacs lets go: the dialog was answered in the TUI,
#                  or the turn moved on.  Print nothing.
#
# Printing nothing leaves CC exactly as without this hook, so every
# failure here -- no answer in time, a killed hook, a word we do not
# know -- falls back to the dialog.
#
# Measured on CC 2.1.332: CC ends a waiting hook with SIGTERM after
# 600 s when settings.json gives no `timeout'; the dialog stays.  We
# give up before that.  A dialog answered in the TUI does NOT end the
# hook; Emacs's empty answer does.
HOLD_SECONDS="${CC_BRIDGE_HOLD_SECONDS:-540}"
HOLD_DIR=""
hold_for_answer() {   # hold_for_answer <payload-file> <iterm-id>; never returns
  local verb
  HOLD_DIR=$(mktemp -d -t "cc-bridge-hold.XXXXXX") || return 1
  trap '[ -n "$HOLD_DIR" ] && rm -rf "$HOLD_DIR"' EXIT
  trap 'log "hold: signalled, giving up"; exit 0' TERM INT HUP
  echo $$ > "$HOLD_DIR/pid"
  log "hold: waiting in $HOLD_DIR (up to ${HOLD_SECONDS}s)"
  if ! emacsclient --no-wait \
         --eval "($hold_fn \"$1\" \"$2\" \"$HOLD_DIR\")" >/dev/null 2>&1; then
    log "hold: emacsclient call failed"
    exit 0
  fi
  SECONDS=0
  while [ ! -e "$HOLD_DIR/answer" ] && [ "$SECONDS" -lt "$HOLD_SECONDS" ]; do
    sleep 0.2
  done
  if [ ! -e "$HOLD_DIR/answer" ]; then
    log "hold: no answer in ${HOLD_SECONDS}s, leaving it to the TUI"
    exit 0
  fi
  verb=$(tr -d '[:space:]' < "$HOLD_DIR/answer" 2>/dev/null)
  log "hold: answer='${verb}' after ${SECONDS}s"
  case "$verb" in
    allow)
      jq -cn '{hookSpecificOutput:{hookEventName:"PermissionRequest",
               decision:{behavior:"allow"}}}' ;;
    allow-always)
      printf '%s' "$input" \
        | jq -c '{hookSpecificOutput:{hookEventName:"PermissionRequest",
                  decision:{behavior:"allow",
                            updatedPermissions:(.permission_suggestions // [])}}}' ;;
    deny)
      jq -cn '{hookSpecificOutput:{hookEventName:"PermissionRequest",
               decision:{behavior:"deny",
                         message:"The user declined this from Emacs.",
                         interrupt:true}}}' ;;
    *) ;;
  esac
  exit 0
}
hold_fn=claude-code-bridge--on-permission-hold-from-file

# ── Spool: events Emacs could not take ───────────────────────────────
# When the local Emacs does not answer (restarting, hung, bridge not
# loaded yet) the event used to be dropped: a turn that ended meanwhile
# never showed its reply.  Now the events that still mean something
# later are saved, one file each, and Emacs replays them when it is
# back (claude-code-bridge-spool.el): at load, and when the next event
# that does get through finds the folder not empty (below).
#
# A file is a header line -- event, iTerm id, seconds since the epoch,
# tab-separated -- and then the payload as CC sent it.  It is written
# as `*.part' and renamed, so Emacs never reads half of one.  PreToolUse
# and PostToolUse are not saved: they only matter while they happen.
SPOOL_DIR="${CC_BRIDGE_SPOOL_DIR:-$HOME/.claude/cc-bridge-spool}"
SPOOL_MAX=500
spool_event() {
  local name count
  case "$event" in
    stop|stop-failure|prompt-submit|notify|permreq) ;;
    *) return 0 ;;
  esac
  mkdir -p "$SPOOL_DIR" 2>/dev/null || { log "spool: cannot make $SPOOL_DIR"; return 0; }
  count=$(ls -1 "$SPOOL_DIR" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${count:-0}" -ge "$SPOOL_MAX" ]; then
    log "spool: full ($count files), event dropped"
    return 0
  fi
  name="$(date +%s.%N)-$$.$event"
  if { printf '%s\t%s\t%s\n' "$event" "${ITERM_SESSION_ID:-}" "$(date +%s)"
       printf '%s' "$input"; } > "$SPOOL_DIR/$name.part" 2>/dev/null \
     && mv "$SPOOL_DIR/$name.part" "$SPOOL_DIR/$name.json" 2>/dev/null; then
    log "spool: saved $name.json"
  else
    rm -f "$SPOOL_DIR/$name.part" 2>/dev/null
    log "spool: could not write $name"
  fi
}

log "fired: ${input:0:200}"

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session_id" ] && fail "no session_id"

# ── Tier 1: local emacsclient ──
if [ -z "${SSH_CONNECTION:-}" ]; then
  command -v emacsclient >/dev/null 2>&1 || fail "no emacsclient"
  # One round trip says whether the bridge is there, and for `permreq'
  # also whether this Emacs can answer a waiting hook.
  probe_expr="(and (fboundp (quote $ec_fn)) t)"
  [ "$event" = permreq ] && probe_expr="(cond ((fboundp (quote $hold_fn)) (quote hold)) ((fboundp (quote $ec_fn)) t))"
  probe=$(timeout 2s emacsclient --eval "$probe_expr" 2>/dev/null \
            | tr -d '[:space:]"')
  case "$probe" in
    t|hold) ;;
    *) spool_event
       fail "bridge not loaded / emacs unreachable" ;;
  esac
  # Emacs is back and events are waiting: have them replayed before this
  # one is delivered, so that they arrive in the order they happened.
  if [ -n "$(ls -A "$SPOOL_DIR" 2>/dev/null)" ]; then
    log "spool: asking Emacs to replay"
    emacsclient --no-wait \
      --eval "(and (fboundp (quote claude-code-bridge-spool-drain)) (claude-code-bridge-spool-drain))" \
      >/dev/null 2>&1 || log "spool: replay call failed"
  fi

  # `$ITERM_SESSION_ID' is set by iTerm in every pane (via the
  # `Setting environment variables' integration) and cascades down
  # through the shell → CC → CC's hook child.  This is the ONLY
  # place the (uuid → iTerm pane id) binding is known to be
  # ground-truth — passed to elisp here so the bridge can cache it
  # for handoff resolution.  Empty when not running under iTerm.
  iterm_iid="${ITERM_SESSION_ID:-}"
  payload=$(mktemp -t "cc-bridge-payload.XXXXXX") || fail "mktemp payload"
  printf '%s' "$input" > "$payload" || { rm -f "$payload"; fail "write payload"; }
  log "local emacsclient → $payload  iid=${iterm_iid:-<none>}"
  # Wait for Emacs's answer when it can give one.  Comes back only when
  # the directory could not be made; then tell Emacs as before.
  [ "$probe" = hold ] && hold_for_answer "$payload" "$iterm_iid"
  emacsclient --no-wait \
    --eval "($ec_fn \"$payload\" \"$iterm_iid\")" >/dev/null 2>&1 \
    || log "emacsclient call failed"
  [[ "$event" == "pretool" ]] && emit_defer
  exit 0
fi

# ── Tier 2: remote — rmate reverse-tunnel ──
command -v rmate >/dev/null 2>&1 || fail "no rmate on remote"
host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
display_name="${rmate_prefix}||${host}"

payload=$(mktemp -t "cc-bridge-payload.XXXXXX") || fail "mktemp payload"
printf '%s' "$input" > "$payload" || { rm -f "$payload"; fail "write payload"; }
log "remote rmate → $display_name  payload=$payload"
timeout 5s rmate -m "$display_name" "$payload" 2>>"$LOG" \
  || log "rmate exit=$?"
rm -f "$payload"
[[ "$event" == "pretool" ]] && emit_defer
exit 0
