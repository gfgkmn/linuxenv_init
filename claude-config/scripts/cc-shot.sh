#!/bin/bash
# cc-shot.sh — the ONLY sanctioned screenshot path for Claude Code.
#
# Why this exists: the agent must not be able to capture arbitrary screen
# content. This script never accepts raw coordinates; it resolves the capture
# rectangle itself from an allowlisted application's window bounds. Combined
# with hooks/enforce-shot.sh (which denies bare `screencapture`), the allowlist
# file is the single authorization surface the user controls.
#
# Usage:
#   cc-shot.sh window <ProcessName> [outfile]   capture one app window
#   cc-shot.sh sim [outfile]                    capture the booted simulator
#   cc-shot.sh list                             show allowed targets
#
# Exit codes: 0 ok, 1 usage/target error, 2 capture failed.

set -euo pipefail

ALLOWLIST="${CC_SHOT_ALLOWLIST:-$HOME/.claude/shot-allowlist}"
OUTDIR="${CC_SHOT_OUTDIR:-$HOME/Temp/cc-shots}"
# Needs pyobjc-framework-Quartz for window-id lookup; pinned to the interpreter
# it was installed into rather than whatever `python3` happens to resolve to.
PYTHON="${CC_SHOT_PYTHON:-/opt/homebrew/bin/python3.10}"

die() { echo "cc-shot: $*" >&2; exit 1; }

allowed_targets() {
  [ -f "$ALLOWLIST" ] || die "allowlist not found: $ALLOWLIST"
  grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST" | sed 's/[[:space:]]*$//'
}

is_allowed() {
  local want="$1" line
  while IFS= read -r line; do
    [ "$line" = "$want" ] && return 0
  done < <(allowed_targets)
  return 1
}

new_outfile() {
  mkdir -p "$OUTDIR"
  echo "$OUTDIR/$1-$(date +%Y%m%d-%H%M%S).png"
}

mode="${1:-}"
[ -n "$mode" ] || die "usage: cc-shot.sh {window <ProcessName>|sim|list} [outfile]"
shift

case "$mode" in
  list)
    echo "Allowlist ($ALLOWLIST):"
    allowed_targets | sed 's/^/  /'
    ;;

  displays)
    # Universal Control presents another Mac's screen as an extra display that
    # Quartz reports as online, which silently inflates the monitor count. Only
    # displays that system_profiler also knows about are physically attached.
    physical=$(system_profiler SPDisplaysDataType 2>/dev/null \
               | grep -cE '^ {8}[A-Za-z].*:$' || true)
    "$PYTHON" - "$physical" <<'PYEOF'
import sys, Quartz
physical = int(sys.argv[1] or 0)
err, ids, cnt = Quartz.CGGetActiveDisplayList(16, None, None)
print("Quartz active displays: %d   system_profiler physical: %d" % (cnt, physical))
if cnt > physical:
    print("  -> %d display(s) reported by Quartz are NOT physically attached"
          % (cnt - physical))
    print("     (Universal Control / virtual display). Treat the physical count"
          " as authoritative.")
for d in ids[:cnt]:
    b = Quartz.CGDisplayBounds(d)
    print("  id=%-4s %4dx%-4d at (%5d,%5d) builtin=%s vendor=%s"
          % (d, int(b.size.width), int(b.size.height),
             int(b.origin.x), int(b.origin.y),
             bool(Quartz.CGDisplayIsBuiltin(d)), Quartz.CGDisplayVendorNumber(d)))
PYEOF
    ;;

  sim)
    out="${1:-$(new_outfile simulator)}"
    # simctl can only ever reach the simulator, so no allowlist check is
    # needed here — it cannot be pointed at the user's other windows.
    xcrun simctl io booted screenshot "$out" >/dev/null 2>&1 \
      || { echo "cc-shot: simctl screenshot failed (is a simulator booted?)" >&2; exit 2; }
    echo "$out"
    ;;

  window)
    app="${1:-}"
    [ -n "$app" ] || die "usage: cc-shot.sh window <ProcessName> [outfile]"
    shift || true
    out="${1:-$(new_outfile "$app")}"

    is_allowed "$app" || {
      echo "cc-shot: '$app' is NOT in the allowlist — refusing." >&2
      echo "cc-shot: allowed targets are:" >&2
      allowed_targets | sed 's/^/  /' >&2
      exit 1
    }

    # Resolve the real CGWindowID owned by the allowlisted process. Capturing
    # by window id (rather than by screen rectangle) means we get that window's
    # own content: an overlapping window, a notification banner, or anything
    # else on top of it is never included.
    # Search ALL windows, not just on-screen ones: a window that is minimised
    # or sitting on another Space still has a capturable id, and the away-from-
    # desk case is exactly when that happens. Prints "<id> <onscreen>".
    read -r wid onscreen <<< "$("$PYTHON" - "$app" <<'PYEOF' 2>/dev/null || true
import sys
from Quartz import (CGWindowListCopyWindowInfo, kCGWindowListOptionAll,
                    kCGNullWindowID)
want = sys.argv[1]
best = None
for w in CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID) or []:
    if w.get("kCGWindowOwnerName") != want:
        continue
    if w.get("kCGWindowLayer", 0) != 0:      # skip menubar items, overlays
        continue
    b = w.get("kCGWindowBounds") or {}
    area = (b.get("Width") or 0) * (b.get("Height") or 0)
    if area < 100000:                         # skip toolbars/title strips
        continue
    if best is None or area > best[1]:
        best = (int(w["kCGWindowNumber"]), area, bool(w.get("kCGWindowIsOnscreen")))
print("%d %s" % (best[0], "yes" if best[2] else "no") if best else "")
PYEOF
)"
    if [ -z "${wid:-}" ]; then
      echo "cc-shot: no capturable window found for '$app' (running, but no real window?)" >&2
      exit 2
    fi

    # An off-screen window (minimised, or on another Space) may hand back the
    # last frame the system cached rather than live content, so say so in the
    # filename — a stale shot must never be mistaken for the current state.
    if [ "$onscreen" = "no" ]; then
      out="${out%.png}-offscreen.png"
    fi

    # -o drops the drop shadow; -l targets exactly that window.
    screencapture -x -o -l"$wid" "$out" \
      || { echo "cc-shot: screencapture failed for window $wid" >&2; exit 2; }
    echo "$out"
    [ "$onscreen" = "no" ] && echo "cc-shot: NOTE window was off-screen; image may be a cached frame" >&2
    ;;

  *)
    die "unknown mode '$mode' (expected: window, sim, list)"
    ;;
esac
