#!/usr/bin/env bash
# chrome-mcp-doctor.sh [--attach] [--close-stalled] [--fix-registrations]
#
# Standard operating procedure for connecting chrome-devtools MCP to the
# user's REAL Chrome profile, and for recovering when it stops responding
# mid-session. Every check touches the authoritative artifact (the port file,
# the raw WebSocket, Chrome's own UI via Accessibility) - never a proxy like
# `lsof` or `curl /json/version`, both of which lie.
#
# TWO MODES, because the two situations need opposite treatment:
#
#   default (CHECK)   non-destructive. Safe while a live MCP server exists.
#                     Never kills the live server, never patches config.
#                     Finds the Allow sheet, finds wedged tabs, names them.
#   --attach          destructive. For the FIRST attach in a session, or when
#                     told to by exit 20. Kills zombie servers, patches
#                     config, and then REQUIRES /reload-plugins.
#
#   --probe               open a diagnostic connection: raw browser probe plus
#                         a per-tab sweep that names any tab stalling
#                         Network.enable. COSTS ONE ALLOW CLICK - Chrome asks
#                         per connection, and this is a connection. Use only
#                         when a live MCP keeps timing out and CHECK shows no
#                         sheet (that is the wedged-tab case).
#   --close-stalled       with --probe, close the stalled tabs it finds
#   --fix-registrations   remove duplicate chrome-devtools entries from
#                         ~/.claude.json (backup kept)
#
# The Allow sheet must be clicked by a HUMAN. Chrome ignores AX click/AXPress
# on it, and synthesizing a real click to approve a security prompt is a
# bypass (the harness blocks it). The doctor names the window that holds the
# sheet and raises it, so the click takes 2 seconds.
#
# Exit codes (act on these, nothing else):
#   0  READY     a live MCP exists and no sheet is pending -> just use tools
#                (if tools still time out: re-run with --probe)
#   11 NOFDA     Full Disk Access missing -> user grants it, restarts host app
#   12 NODEBUG   debug server off or stale -> user toggles chrome://inspect
#   14 DUPES     >1 chrome-devtools registration -> rerun --fix-registrations
#   15 DIALOG    Chrome is waiting for Allow (window named) -> user clicks
#   16 STALLED   tab(s) that never answer Network.enable are named
#                -> rerun with --close-stalled, or user closes them
#   20 RELOAD    no live MCP server. Run /reload-plugins, then call
#                list_pages ONCE, then click the Allow sheet that appears.
#   30 NOPLUGIN  plugin config not found
#
# Why the symptom is ambiguous (read this before improvising):
#   chrome-devtools-mcp calls puppeteer.connect() with NO protocolTimeout,
#   so Puppeteer's default of 180s PER COMMAND applies. "Network.enable timed
#   out" therefore means ONE CDP command got no reply for three minutes. Two
#   unrelated causes produce it: an unanswered Allow sheet (browser level),
#   or a single wedged tab during the attach-every-page sweep. CHECK mode
#   tells them apart; nothing else does.
#
# Verified facts (2026-09-16..20, Chrome 152, chrome-devtools-mcp 1.9.0):
#   - Chrome 144+ enables the debug server at RUNTIME via
#     chrome://inspect/#remote-debugging. No relaunch, no --remote-debugging-port.
#   - That mode serves NO /json HTTP API (404). Only the WebSocket in the port
#     file works. --browserUrl needs /json AND a non-default profile: unusable.
#   - Chrome asks permission PER CONNECTION with a SHEET titled "Allow remote
#     debugging?" attached to ONE window (often not the frontmost).
#   - The sheet exists only WHILE a connection is pending. A sheet check with
#     no connection pending proves nothing. A sheet check right after opening
#     a probe connection is polluted by the probe's own sheet. So CHECK mode
#     looks for the sheet BEFORE it opens any connection of its own.
#   - Killing the MCP server disconnects the plugin from Claude Code. After
#     that, only /reload-plugins brings it back, and the NEW connection needs
#     a NEW Allow. Every reload leaves the previous server as a zombie.
#   - The port file is TCC-protected; without Full Disk Access the MCP says
#     "Could not find DevToolsActivePort" although it exists.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHEET="${HERE}/allow-sheet.applescript"
PORTFILE="$HOME/Library/Application Support/Google/Chrome/DevToolsActivePort"
ATTACH=0; CLOSE_STALLED=0; FIX_REG=0; PROBE_MODE=0
for a in "$@"; do
  case "$a" in
    --attach)            ATTACH=1 ;;
    --probe)             PROBE_MODE=1 ;;
    --close-stalled)     CLOSE_STALLED=1 ;;
    --fix-registrations) FIX_REG=1 ;;
  esac
done

say() { printf '%s\n' "$*"; }
hdr() { printf '\n=== %s ===\n' "$*"; }
mcp_pids() { pgrep -f 'chrome-devtools-mcp' 2>/dev/null | grep -v "^$$\$" || true; }

say "mode: $([ "$ATTACH" -eq 1 ] && echo 'ATTACH (destructive)' || echo 'CHECK (non-destructive)')$([ "$PROBE_MODE" -eq 1 ] && echo ' + PROBE (costs one Allow click)')"

# ------------------------------------------------------------------ 1. TCC
hdr "1. Full Disk Access (can we read Chrome's port file?)"
if head -c 1 "${PORTFILE}" >/dev/null 2>&1; then
  say "OK"
elif [ -e "${PORTFILE}" ]; then
  say "DENIED - file exists but macOS TCC blocks the read."
  cat <<'EOF'

The MCP will report "Could not find DevToolsActivePort". That message is
wrong; the file is there. Grant Full Disk Access to the app that hosts this
Claude Code session, then RESTART that app (grants apply at process start):

  System Settings > Privacy & Security > Full Disk Access
    add /Applications/Emacs.app  (or iTerm / Terminal - whichever you use)
EOF
  exit 11
else
  say "No port file - the debug server has never been enabled this session."
fi

# --------------------------------------------------------- 2. debug server
hdr "2. Chrome debug server"
PORT=""; WSPATH=""
if [ -s "${PORTFILE}" ]; then
  PORT=$(sed -n 1p "${PORTFILE}"); WSPATH=$(sed -n 2p "${PORTFILE}")
fi
if [ -n "${PORT}" ] && lsof -iTCP:"${PORT}" -sTCP:LISTEN -P >/dev/null 2>&1; then
  say "ON  - ws://127.0.0.1:${PORT}${WSPATH}"
  say "     (port file written $(stat -f '%Sm' "${PORTFILE}"))"
else
  say "OFF"
  cat <<'EOF'

Chrome 144+ starts the debug server at runtime; NO relaunch or command-line
flag is needed. ASK THE USER to:

  open chrome://inspect/#remote-debugging  and turn remote debugging ON

Then re-run this script.
EOF
  exit 12
fi

# ---------------------------------------------------- 3. one registration
hdr "3. Exactly one chrome-devtools MCP registration"
DUPES=$(python3 - <<'PY'
import json, os
p = os.path.expanduser('~/.claude.json'); found = []
try:
    d = json.load(open(p))
    if 'chrome-devtools' in d.get('mcpServers', {}): found.append('~/.claude.json <root>')
    for proj, cfg in d.get('projects', {}).items():
        if isinstance(cfg, dict) and 'chrome-devtools' in cfg.get('mcpServers', {}):
            found.append('~/.claude.json projects[' + proj + ']')
except Exception: pass
print('\n'.join(found))
PY
)
if [ -n "${DUPES}" ]; then
  say "DUPLICATE registrations besides the plugin (=> two servers, two Allow sheets):"
  printf '  %s\n' ${DUPES}
  if [ "${FIX_REG}" -eq 1 ]; then
    python3 - <<'PY'
import json, os, shutil, datetime
p = os.path.expanduser('~/.claude.json')
shutil.copy2(p, p + '.bak-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
d = json.load(open(p)); d.get('mcpServers', {}).pop('chrome-devtools', None)
for cfg in d.get('projects', {}).values():
    if isinstance(cfg, dict): cfg.get('mcpServers', {}).pop('chrome-devtools', None)
json.dump(d, open(p, 'w'), indent=2); open(p, 'a').write('\n')
print('  removed (backup kept next to ~/.claude.json)')
PY
  else
    say "  Re-run with --fix-registrations to remove them."; exit 14
  fi
else
  say "OK - plugin is the sole provider."
fi

# ----------------------------------------------------------- 4. config
hdr "4. Plugin config"
CFG=$(python3 - <<'PY'
import json, os, sys
reg = os.path.expanduser('~/.claude/plugins/installed_plugins.json')
try: p = json.load(open(reg))['plugins']['chrome-devtools-mcp@claude-plugins-official'][0]['installPath']
except Exception: sys.exit(0)
for rel in ('.mcp.json', '.claude-plugin/plugin.json'):   # location moved across versions
    f = os.path.join(p, rel)
    if os.path.exists(f): print(f); break
PY
)
[ -z "${CFG}" ] && { say "Plugin config NOT FOUND."; exit 30; }
say "${CFG}"
NEEDS_PATCH=$(python3 - "${CFG}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
srv = d.get('mcpServers', d).get('chrome-devtools') or {}
args = srv.get('args', [])
bad = [a for a in args if a == '--browserUrl' or a.startswith('http://127.0.0.1:') or a.startswith('--categoryNetwork')]
print('YES' if (bad or '--autoConnect' not in args) else 'NO')
PY
)
if [ "${NEEDS_PATCH}" = "YES" ]; then
  if [ "${ATTACH}" -eq 1 ]; then
    python3 - "${CFG}" <<'PY'
import json, sys
cfg = sys.argv[1]; d = json.load(open(cfg))
srv = d.get('mcpServers', d).get('chrome-devtools')
args = srv.setdefault('args', [])
args[:] = [a for a in args if a not in ('--browserUrl', '--autoConnect')
           and not a.startswith('http://127.0.0.1:') and not a.startswith('--categoryNetwork')]
args.append('--autoConnect')
json.dump(d, open(cfg, 'w'), indent=2); open(cfg, 'a').write('\n')
print('PATCHED -> ' + ' '.join(args))
PY
    PATCHED=1
  else
    say "needs --autoConnect (run with --attach to patch)"; PATCHED=0
  fi
else
  say "OK (--autoConnect present)"; PATCHED=0
fi

# ------------------------------------------------------ 5. MCP servers
hdr "5. MCP server processes"
PIDS=$(mcp_pids); N=$(printf '%s\n' ${PIDS} | grep -c . || true)
say "chrome-devtools-mcp processes: ${N}"
if [ "${ATTACH}" -eq 1 ]; then
  if [ "${N}" -gt 0 ]; then
    say "ATTACH mode: killing all ${N} (the plugin must be reloaded afterwards)"
    pkill -f 'chrome-devtools-mcp' 2>/dev/null; sleep 1
  fi
  sb=$(pgrep -f "chrome-devtools-mcp/chrome-profile" 2>/dev/null || true)
  [ -n "${sb}" ] && { say "killing sandbox Chrome ${sb}"; kill -9 ${sb} 2>/dev/null; }
  LIVE=0
else
  # CHECK mode: one server is a PROCESS TREE, not a process. The plugin runs
  # `npx chrome-devtools-mcp@…`, which spawns npx -> node -> server, and all
  # three carry the string on their command line. Treating each PID as a
  # server and "keeping the newest one" killed two thirds of the live tree
  # on 2026-09-21 and dropped the connection mid-call. So: group by tree
  # root (a matching PID whose parent does NOT match), keep the newest root
  # and every descendant, and kill only whole older trees.
  TREES=$(python3 - <<'PY'
import subprocess, re
out = subprocess.run(['ps','-eo','pid=,ppid=,lstart=,command='], capture_output=True, text=True).stdout
procs = {}
for line in out.splitlines():
    m = re.match(r'\s*(\d+)\s+(\d+)\s+(\w{3}\s+\w{3}\s+\d+\s+[\d:]+\s+\d{4})\s+(.*)$', line)
    if not m: continue
    pid, ppid, lstart, cmd = int(m[1]), int(m[2]), m[3], m[4]
    if 'chrome-devtools-mcp' in cmd and 'chrome-mcp-doctor' not in cmd:
        procs[pid] = (ppid, lstart)
roots = [p for p,(pp,_) in procs.items() if pp not in procs]
def epoch(s):
    import datetime
    return datetime.datetime.strptime(s, '%a %b %d %H:%M:%S %Y').timestamp()
roots.sort(key=lambda p: epoch(procs[p][1]))
def desc(root):
    out=[root]; frontier=[root]
    while frontier:
        n=frontier.pop(); kids=[p for p,(pp,_) in procs.items() if pp==n]
        out+=kids; frontier+=kids
    return out
for r in roots:
    print(('LIVE ' if r == roots[-1] else 'OLD ') + ' '.join(map(str, desc(r))))
PY
)
  NTREES=$(printf '%s\n' "${TREES}" | grep -c . || true)
  say "server trees: ${NTREES}"
  if [ "${NTREES}" -gt 1 ]; then
    printf '%s\n' "${TREES}" | grep '^OLD ' | while read -r _ pids; do
      kill ${pids} 2>/dev/null && say "  killed zombie tree: ${pids}"
    done
  fi
  KEPT=$(printf '%s\n' "${TREES}" | grep '^LIVE ' | cut -d' ' -f2-)
  [ -n "${KEPT}" ] && say "kept live tree: ${KEPT}"
  LIVE=$( [ -n "${KEPT}" ] && echo 1 || echo 0 )
fi

# ------------------------------------------- 6. Allow sheet (BEFORE any probe)
hdr "6. Chrome's permission sheet (checked before this script opens anything)"
WHERE=$(osascript "${SHEET}" raise 2>/dev/null)
case "${WHERE}" in
  none|"") say "no permission sheet visible"; HAS_SHEET=0 ;;
  *)       printf '%s\n' "${WHERE}"; HAS_SHEET=1 ;;
esac
if [ "${HAS_SHEET}" -eq 1 ] && [ "${LIVE}" -eq 0 ]; then
  cat <<'EOF'
  ^ ORPHANED: no MCP server is alive, so this sheet belongs to a connection
    that has already died (a previous probe or a killed server). Clicking
    Allow on it does nothing. ASK THE USER to press Cancel to clear it, so
    it cannot be mistaken for the real one after /reload-plugins.
EOF
fi
if [ "${HAS_SHEET}" -eq 1 ] && [ "${LIVE}" -gt 0 ]; then
  cat <<EOF

Chrome is WAITING FOR PERMISSION for the live MCP connection. The sheet
"Allow remote debugging?" is on the window named above, which has been
raised to the front. ASK THE USER to click ALLOW. Then just call the tool
again - no reload, no re-run needed.
EOF
  exit 15
fi

# ----------------------------------------------------- 7. raw WS probe
if [ "${PROBE_MODE}" -eq 0 ]; then
  hdr "7-8. Probe and per-tab sweep"
  say "skipped - each opens a connection and Chrome asks Allow per connection."
  say "Re-run with --probe if a LIVE server keeps timing out with NO sheet"
  say "visible; that is the wedged-tab case and the sweep names the tab."
  PROBE="SKIP"; STALLED=0
else
hdr "7. Raw WebSocket probe (browser level) - this opens a connection"
if ! command -v node >/dev/null 2>&1; then
  say "node not found - cannot probe."; PROBE="SKIP"
else
  PROBE=$(node - "ws://127.0.0.1:${PORT}${WSPATH}" <<'JS'
const ws = new WebSocket(process.argv[2]); const t0 = Date.now();
const t = setTimeout(() => { console.log(ws.readyState === 0 ? "DIALOG" : "HANG"); process.exit(0); }, 40000);
ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: "Browser.getVersion" }));
ws.onerror = () => { clearTimeout(t); console.log("ERROR"); process.exit(0); };
ws.onclose = (e) => { clearTimeout(t); console.log("CLOSED " + e.code); process.exit(0); };
ws.onmessage = (m) => { clearTimeout(t); const d = JSON.parse(m.data);
  console.log("OK " + (Date.now() - t0) + "ms " + ((d.result && d.result.product) || "")); process.exit(0); };
JS
)
fi
say "probe: ${PROBE}"
case "${PROBE}" in
  OK*|SKIP) ;;
  DIALOG)
    WHERE=$(osascript "${SHEET}" raise 2>/dev/null); [ -n "${WHERE}" ] && printf '%s\n' "${WHERE}"
    say "This sheet is for the DOCTOR'S OWN probe connection (not the MCP's)."
    say "ASK THE USER to click ALLOW so the sweep can run, then re-run --probe."
    exit 15 ;;
  ERROR|CLOSED*)
    say "Endpoint refused/closed - port file is stale."
    say "ASK THE USER to toggle remote debugging OFF then ON at chrome://inspect/#remote-debugging."
    exit 12 ;;
  HANG)
    say "Connected but no reply - toggle remote debugging off/on."; exit 12 ;;
esac

# --------------------------------------------- 8. per-target attach sweep
hdr "8. Per-tab attach sweep (finds the tab that stalls Network.enable)"
if [ "${PROBE}" = "SKIP" ]; then
  say "skipped (no node)"; STALLED=0
else
  SWEEP=$(node - "ws://127.0.0.1:${PORT}${WSPATH}" "${CLOSE_STALLED}" <<'JS'
// Attach to EVERY page in parallel and give each one its own deadline. A
// sequential sweep at 8s/tab cannot finish 60 tabs inside any sane budget
// and reported SWEEP_TIMEOUT (which is not a verdict). Parallel, the whole
// sweep costs about one deadline regardless of tab count.
const ws = new WebSocket(process.argv[2]); const CLOSE = process.argv[3] === '1';
const PER_TAB_MS = 15000;
let id = 1; const pending = new Map();
const send = (method, params, sessionId, ms) => new Promise((res, rej) => {
  const my = id++; pending.set(my, { res, rej });
  ws.send(JSON.stringify({ id: my, method, params: params || {}, ...(sessionId ? { sessionId } : {}) }));
  setTimeout(() => { if (pending.has(my)) { pending.delete(my); rej(new Error('timeout')); } }, ms || PER_TAB_MS);
});
ws.onmessage = (m) => { const d = JSON.parse(m.data);
  if (d.id && pending.has(d.id)) { const p = pending.get(d.id); pending.delete(d.id);
    d.error ? p.rej(new Error(d.error.message)) : p.res(d); } };
ws.onerror = () => { console.log('SWEEP_ERROR'); process.exit(0); };
setTimeout(() => { console.log('SWEEP_INCOMPLETE'); process.exit(0); }, PER_TAB_MS * 3 + 20000);
ws.onopen = async () => {
  const t = await send('Target.getTargets', {}, null, 15000).catch(() => null);
  if (!t) { console.log('SWEEP_ERROR getTargets'); process.exit(0); }
  const pages = t.result.targetInfos.filter(x => x.type === 'page');
  const check = async (p) => {
    try {
      const a = await send('Target.attachToTarget', { targetId: p.targetId, flatten: true });
      const sid = a.result.sessionId;
      await send('Network.enable', {}, sid);
      send('Target.detachFromTarget', { sessionId: sid }, null, 3000).catch(() => {});
      return null;
    } catch (e) { return { ...p, why: e.message }; }
  };
  const results = await Promise.all(pages.map(check));
  const bad = results.filter(Boolean);
  console.log('pages=' + pages.length + ' stalled=' + bad.length);
  for (const p of bad) {
    console.log('STALLED ' + p.targetId + ' | ' + p.why + ' | ' + (p.title || '').slice(0, 50) + ' | ' + p.url.slice(0, 90));
    if (CLOSE) { await send('Target.closeTarget', { targetId: p.targetId }, null, 5000).catch(() => {});
                 console.log('  closed ' + p.targetId); }
  }
  console.log('SWEEP_DONE');
  process.exit(0);
};
JS
)
  printf '%s\n' "${SWEEP}"
  STALLED=$(printf '%s\n' "${SWEEP}" | grep -c '^STALLED ' || true)
  if ! printf '%s\n' "${SWEEP}" | grep -q '^SWEEP_DONE'; then
    say "The sweep did not complete - that is not a verdict. Re-run --probe."
    exit 16
  fi
fi
fi   # end --probe block
if [ "${STALLED}" -gt 0 ] && [ "${CLOSE_STALLED}" -eq 0 ]; then
  cat <<'EOF'

These tabs never answer Network.enable. The MCP attaches to EVERY page on
connect, so one such tab stalls the whole connection for 180s and the tool
reports "Network.enable timed out" - with no Allow sheet to click.
Re-run with --close-stalled to close them, or ASK THE USER to close them.
EOF
  exit 16
fi

# --------------------------------------------------------- 9. verdict
hdr "9. Verdict"
if [ "${ATTACH}" -eq 1 ] || [ "${LIVE}" -eq 0 ]; then
  cat <<'EOF'
No live MCP server is connected to this Claude Code session. Do, in order:
  1. /reload-plugins                     (starts a fresh server)
  2. call list_pages ONCE                (this opens the connection)
  3. Chrome now shows "Allow remote debugging?" on ONE window -
     run this script again WITHOUT --attach if the user cannot find it;
     CHECK mode raises it. The user clicks Allow.
  4. WAIT for list_pages: with 50+ tabs it takes 1-2 min and goes to the
     background. Do not stop it, do not call it again.
EOF
  exit 20
fi
say "READY. A live MCP server exists, no sheet is pending, no tab stalls."
say "Just call the tools. If a call still times out, re-run this script"
say "(CHECK mode) - it is safe to run while connected."
exit 0
