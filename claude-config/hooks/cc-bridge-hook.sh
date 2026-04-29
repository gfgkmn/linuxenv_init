#!/usr/bin/env bash
# cc-bridge-hook.sh — unified Claude Code hook dispatcher for the bridge.
#
# Events: stop | prompt-submit | notify | pretool | posttool
#
# All events are fire-and-forget except `pretool', which still emits a
# JSON `defer' to stdout so CC's TUI handles the actual permission
# decision.  Emacs is notify-only — it never decides for CC.
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

log "fired: ${input:0:200}"

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session_id" ] && fail "no session_id"

# ── Tier 1: local emacsclient ──
if [ -z "${SSH_CONNECTION:-}" ]; then
  command -v emacsclient >/dev/null 2>&1 || fail "no emacsclient"
  probe=$(timeout 2s emacsclient --eval "(and (fboundp (quote $ec_fn)) t)" 2>/dev/null \
            | tr -d '[:space:]"')
  [ "$probe" = "t" ] || fail "bridge not loaded / emacs unreachable"

  payload=$(mktemp -t "cc-bridge-payload.XXXXXX") || fail "mktemp payload"
  printf '%s' "$input" > "$payload" || { rm -f "$payload"; fail "write payload"; }
  log "local emacsclient → $payload"
  emacsclient --no-wait --eval "($ec_fn \"$payload\")" >/dev/null 2>&1 \
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
