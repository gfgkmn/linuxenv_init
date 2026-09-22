---
name: chrome-mcp-attach
description: Connect chrome-devtools MCP to the user's real Chrome (real profile, tabs, logins), and recover it when it stops answering mid-session. Use whenever a chrome-devtools tool fails — "Could not find DevToolsActivePort", "Could not connect to Chrome", "Network.enable timed out", list_pages hanging or returning only about:blank — or when the user asks to attach/fix/reconnect Chrome MCP. Run the doctor script FIRST; never hand-diagnose. Never run any diagnostic that opens its own connection unless the doctor tells you to — every connection costs the user an Allow click.
allowed-tools: Bash, Read, Edit, Write
---

# Chrome MCP — standard operating procedure

```bash
~/.claude/skills/chrome-mcp-attach/scripts/chrome-mcp-doctor.sh          # CHECK: passive, safe, free
~/.claude/skills/chrome-mcp-attach/scripts/chrome-mcp-doctor.sh --attach # first attach / told to by exit 20
~/.claude/skills/chrome-mcp-attach/scripts/chrome-mcp-doctor.sh --probe  # costs ONE Allow click; finds a wedged tab
```

Run the plain doctor. Act on the exit code. Do not improvise, do not retry a
failing tool "to see if it works now", and do not open your own WebSocket,
CDP script or `curl` — **every connection to Chrome costs the user one Allow
click**, including diagnostic ones, and a diagnostic that opens a connection
then reports the sheet it caused. This was measured, not assumed.

| Exit | Meaning | Your action |
|------|---------|-------------|
| `0`  | Live MCP, no sheet pending | Just call tools. Still timing out? → run `--probe` (see below). |
| `15` | **Chrome is waiting for Allow** | The doctor named and raised the window. User clicks Allow. Then call the tool again — no reload, no re-run. |
| `16` | **A tab stalls `Network.enable`** (from `--probe`) | It's named. Re-run `--probe --close-stalled`, or user closes it. Then call the tool again. |
| `20` | **No live MCP server** | Follow the four-step reconnect below. Exactly that order. |
| `11` | Full Disk Access missing | Relay the grant instructions. Stop; nothing else can work. |
| `12` | Debug server off / stale | User toggles `chrome://inspect/#remote-debugging` (off→on if stale). Re-run. |
| `14` | Duplicate registrations | Re-run with `--fix-registrations` (backup of `~/.claude.json` kept). |
| `30` | Plugin not installed | Report and stop. |

## The four-step reconnect (exit 20)

The order matters because the Allow sheet only exists **while a connection
is pending**, and the MCP connects lazily on its first tool call.

1. User runs **`/reload-plugins`** — starts a fresh server. (Any previous
   server is now a zombie; CHECK mode cleans those up next time it runs.)
2. You call **`list_pages` once**. This is what opens the connection. It goes
   to the background after 120 s — that is normal with 50+ tabs. **Do not
   stop it, do not call it again**: a second call is a second connection and
   a second sheet.
3. **While it is pending**, run the plain doctor. CHECK mode finds the MCP's
   sheet and raises its window. User clicks Allow.
4. Wait for the task notification. Then use the tools.

If step 3 finds **no sheet** and `list_pages` still times out, that is the
wedged-tab case → `--probe`.

## The usual real cause: Chrome has discarded most of the tabs

Found 2026-09-21 with the parallel sweep: **39 of 59 tabs** stalled
`Network.enable`. Chrome's memory saver *discards* background tabs it hasn't
shown for a while — the tab stays in the strip, but its renderer is gone.
`Target.attachToTarget` still succeeds against the placeholder; `Network.enable`
needs a live renderer and never answers. The MCP attaches to every page on
connect, so the first discarded tab it hits blocks for Puppeteer's 180 s
default and the whole connection dies.

This is why it "worked earlier and rotted over days": fresh tabs are live,
week-old arxiv/GitHub/artifact tabs are discarded, and no amount of
reloading the plugin changes the tabs. **Not an Allow sheet, not one wedged
tab, not memory pressure.** `--probe` proves it (stalled count ≫ 1);
`--probe --close-stalled` fixes it (Target.closeTarget on each). The
AppleScript tab count lags — verify with the sweep's `page targets` number.

Prevention: keep Chrome's tab count low during MCP work, or turn off
Memory Saver (chrome://settings/performance) for the session. There is no
MCP-side flag: `targetFilter` filters by URL scheme only, and the
`blocklist` isn't exposed on the CLI.

## An INSTANT "Network.enable timed out" means the server is poisoned

Timing tells you which failure you have. A **fresh** attach takes the full
180 s to fail. An **instant** failure (under a second) is a server that
already failed once: `ensureBrowserConnected` returns the existing browser
whenever `browser?.connected` is true, and the browser-level socket *is*
still connected — only the page attach is broken. Every later tool call
gets the same cached failure at once. No change on Chrome's side can reach
it. This is the one case for `--attach` mid-session: replace the server
(`/reload-plugins`), which costs one Allow.

So the order after fixing tabs is: `--probe --close-stalled` → `--attach` →
`/reload-plugins` → `list_pages` once → click Allow. Skipping `--attach`
leaves you retrying against a server that can never succeed.

## The symptom is ambiguous — this is why hand-diagnosis fails

`chrome-devtools-mcp` calls `puppeteer.connect()` with **no `protocolTimeout`**,
so Puppeteer's default of **180 s per command** applies. `Network.enable
timed out` therefore means *one CDP command got no reply for three minutes*.
Two unrelated causes produce the identical message:

- an **unanswered Allow sheet** (browser level) — fix: click it;
- **discarded tabs** during the attach-every-page sweep — usually many, not
  one — fix: `--probe --close-stalled`.

You cannot tell which from the error. CHECK mode tells you (sheet present or
not); `--probe` names the tab. Nothing you improvise will do better, and it
will cost clicks.

## Facts that were each learned the hard way

**Reaching the real profile — the only way.** `chrome://inspect/#remote-debugging`
enables a debug server *at runtime* (Chrome 144+). It writes
`~/Library/Application Support/Google/Chrome/DevToolsActivePort`; `--autoConnect`
reads it and dials the WebSocket. **No `--remote-debugging-port` relaunch is
needed or wanted.**

**TCC.** The port file is in a protected directory. Without Full Disk Access on
the *host app* (Emacs.app here) the read fails and the MCP reports **"Could not
find DevToolsActivePort"** — the file is there; it is *unreadable*.

**One Allow per connection, and orphans linger.** Chrome 144+ asks per
connection with a **sheet** titled "Allow remote debugging?" attached to
**one** window, often not the frontmost. It cannot be automated (AX click and
AXPress are ignored; synthetic input to approve a security prompt is a bypass
the harness refuses). When the connection behind a sheet dies, **the sheet
stays on screen** — an orphan. Clicking Allow on an orphan does nothing;
Cancel clears it. The doctor reports orphans when it sees a sheet with no
live server.

**Killing the server disconnects the plugin.** The old doctor `pkill`ed every
server on every run, *including the live one*, then reported READY. Run
mid-session that guaranteed a reload, a new connection, a new sheet, and one
more zombie — while claiming to have fixed things. That is how a session
reached 17 zombie servers. CHECK mode never kills the newest server.

**A server is a process tree, not a process.** The plugin runs
`npx chrome-devtools-mcp@…`, which spawns npx → node → server; all three carry
the string on their command line. `pgrep -f chrome-devtools-mcp` therefore
returns three PIDs per live server. Any zombie logic that reasons per-PID
("kill all but the newest") kills two thirds of the live tree and drops the
connection mid-call — verified 2026-09-21, `Connection closed`. The doctor
groups by tree root and only ever kills whole *older* trees.

**One registration.** `~/.claude.json` (root or per-project) *and* the plugin
both defining `chrome-devtools` spawns two servers → two Allow sheets. The
plugin is the sole provider; the doctor enforces it.

**Config resets on plugin update** and the file moved from `.mcp.json` to
`.claude-plugin/plugin.json`. `--attach` re-applies `--autoConnect`.

## Instruments that lie (never use as health checks)

| Instrument | Why it lies |
|---|---|
| `lsof … 9222 LISTEN` | `chrome://inspect` **port-forwarding** also listens there and answers 404. |
| `curl /json/version` | Runtime debug mode serves **no /json HTTP API** — 404 on a healthy Chrome 152. |
| "Could not find DevToolsActivePort" | Means *cannot read* (TCC), not *missing*. |
| "Network.enable timed out" | Ambiguous: Allow sheet **or** wedged tab. See above. |
| Browser-level probe says OK | Proves nothing about per-target attach. |
| Sheet-finder run on its own | Meaningless: sheets exist only while a connection is pending, and orphans persist. Only the doctor's ordering (sheet check *before* any probe) gives a true answer. |
| Tab count | Frozen-tab hangs (#1230) were fixed in Chrome 149. But **attach cost** is real: the MCP attaches to every page, so more tabs = longer first call. Not a bug; just wait. |

## Wrong turns already taken (do not repeat)

- `--browserUrl`: needs the /json API (404) **and** a non-default
  user-data-dir — can never reach the real profile.
- Quit-and-relaunch Chrome with a flag: unnecessary since Chrome 144; wrong.
- `--categoryNetwork=false` to dodge `Network.enable`: no effect (verified).
- Auto-clicking Allow (AX or synthetic input): ignored / refused. Stop.
- Patching config then only `/mcp` reconnect: the loader caches config;
  `/reload-plugins` is the load-bearing step.
- Running the destructive doctor mid-session: see "Killing the server". Use
  CHECK mode.
- Freeing memory / shutting down simulators to "unstick" CDP: irrelevant to
  both real causes. Cost an hour on 2026-09-20.
- Hand-written CDP scripts to "find the wedged tab": the right idea in the
  wrong place. That is what `--probe` is; it declares its Allow cost first.

## Non-goals

- Never quit/relaunch the user's Chrome. Never use `--isolated` or a fresh
  `--user-data-dir`.
- Never edit `~/.claude.json` without the user's explicit yes; the doctor only
  does it under `--fix-registrations`, with a backup.
- Never attempt to approve the Allow sheet programmatically.
- Never open a connection of your own outside `--probe`.

## Typing into pages on THIS Chrome: never use `fill` / `type_text`

The user runs the **Surfingkeys** extension (vim-style keyboard control). The
MCP's `fill` and `type_text` tools emit real keystrokes, which Surfingkeys
intercepts as commands. Enter text with `evaluate_script`: set the value
through the native setter and dispatch `input`/`change`. For App Store
Connect's styled-component menus, dispatch **Pointer Events**
(`pointerdown`/`pointerup`) as well as mouse events — `MouseEvent` alone is
silently ignored by its `MenuList`.

```js
const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
set.call(input, value);
input.dispatchEvent(new Event('input',{bubbles:true}));
input.dispatchEvent(new Event('change',{bubbles:true}));
```

## When to re-run

After any plugin update, any Chrome restart (the debug server does not
persist), or whenever a chrome-devtools tool fails. CHECK mode is idempotent
and free; run it as often as you like.
