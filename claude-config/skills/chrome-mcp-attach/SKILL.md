---
name: chrome-mcp-attach
description: Connect chrome-devtools MCP to the user's real Chrome (real profile, tabs, logins). Use whenever a chrome-devtools tool fails — "Could not find DevToolsActivePort", "Could not connect to Chrome", "Network.enable timed out", list_pages hanging or returning only about:blank — or when the user asks to attach/fix/reconnect Chrome MCP. Run the doctor script FIRST; never hand-diagnose.
allowed-tools: Bash, Read, Edit, Write
---

# Chrome MCP — standard operating procedure

```bash
~/.claude/skills/chrome-mcp-attach/scripts/chrome-mcp-doctor.sh
```

Run it. Act on the exit code. Do not improvise, and do not retry a failing
tool call "to see if it works now" — every connection attempt costs the user a
Chrome permission click.

| Exit | Meaning | Your action |
|------|---------|-------------|
| `0`  | Ready | Call `list_pages`. Tell the user: **Chrome will show an "Allow remote debugging?" sheet — click Allow.** If they can't see it, re-run the doctor: it raises the window that holds it. |
| `20` | Config patched | Ask for `/reload-plugins`, then as exit 0. |
| `11` | Full Disk Access missing | Relay the grant instructions. Stop; nothing else can work. |
| `12` | Debug server off / stale | User toggles `chrome://inspect/#remote-debugging` (off→on if stale). Re-run. |
| `14` | Duplicate registrations | Re-run with `--fix-registrations` (backup of `~/.claude.json` kept). |
| `15` | **Chrome is waiting for Allow** | The doctor raised the window holding the sheet and named it. User clicks Allow. Re-run. |
| `30` | Plugin not installed | Report and stop. |

**Patience rule.** After Allow is clicked, the MCP attaches to every tab
before answering. With 50+ tabs the FIRST `list_pages` takes **1–2 minutes**
and gets moved to the background by the harness — that is normal and it is
working. Do NOT stop it, kill the MCP, or call again: every new connection
costs the user another Allow sheet. Wait for the task notification.
(Validated 2026-09-16: 54 tabs, ~2 min, then all tabs listed.)

Connected tool namespace: `mcp__plugin_chrome-devtools-mcp_chrome-devtools__*`.
Visible success: Chrome's **"Chrome is being controlled by automated test
software"** banner.

## The one unavoidable human step

Chrome 144+ asks permission **per connection**: *"every time the Chrome
DevTools MCP server requests a remote debugging session, Chrome will show a
dialog to the user and ask for their permission"* (Chrome DevTools blog). The
dialog is a **sheet** titled **"Allow remote debugging?"**, attached to **one**
Chrome window — often not the frontmost — which is why it goes unnoticed and
every client "times out". Its buttons: *Turn off in settings · Cancel · Allow*.

It cannot be automated, and this was tested, not assumed:
- AX `click` and `perform action "AXPress"` on the Allow button are ignored.
- Synthesizing a real input event to approve a security prompt is a bypass;
  the Claude Code harness refuses it. Do not try again.

So the SOP makes the click trivial instead: the doctor names the window and
raises it to the front. One click per new MCP connection. That is the cost of
controlling a real profile, and it is Chrome's design, not a bug.

## The verified model (every line tested or read in primary docs, 2026-09-16)

**Reaching the real profile — the only way.** `chrome://inspect/#remote-debugging`
enables a debug server *at runtime* (Chrome 144+). It writes
`~/Library/Application Support/Google/Chrome/DevToolsActivePort` (line 1 port,
line 2 browser WebSocket path). `--autoConnect` reads it and dials the
WebSocket. **No `--remote-debugging-port` relaunch is needed or wanted.**

**TCC.** The port file is in a protected directory. Without Full Disk Access on
the *host app* (Emacs.app here) the read fails and the MCP reports **"Could not
find DevToolsActivePort"** — the file is there; it is *unreadable*. Granting FDA
to Emacs and restarting it fixed every process beneath it, including shells
under a launchd-parented tmux server. Probe; don't theorize.

**One registration.** `~/.claude.json` (root or per-project) *and* the plugin
both defining `chrome-devtools` spawns two servers → two Allow sheets, two
attach loops, "zombie" processes (maintainer: zombies mean *the server was not
stopped by the client*). The plugin is the sole provider; the doctor enforces it.

**Config resets on plugin update** (1.7→1.8→1.9 in five weeks) and the file
moved from `.mcp.json` to `.claude-plugin/plugin.json`. The doctor resolves the
path from `installed_plugins.json` and re-applies `--autoConnect` each run.

## Instruments that lie (never use as health checks)

| Instrument | Why it lies |
|---|---|
| `lsof … 9222 LISTEN` | `chrome://inspect` **port-forwarding** also listens there and answers 404. |
| `curl /json/version` | Runtime debug mode serves **no /json HTTP API** — 404 on a healthy Chrome 152. |
| "Could not find DevToolsActivePort" | Means *cannot read* (TCC), not *missing*. |
| "Network.enable timed out" | Means *init window expired* — almost always the unanswered Allow sheet. |
| Tab count | Frozen-tab hangs (#1230) were fixed in **Chrome 149**. 58 tabs was a red herring; splitting them across windows proved it. |

The only truthful probes: reading the port file, opening a raw WebSocket to
the browser endpoint, and asking Accessibility whether the Allow sheet is up.
The doctor uses exactly those.

## Wrong turns already taken (do not repeat)

- `--browserUrl`: needs the /json API (404) **and** a non-default
  user-data-dir (docs) — can never reach the real profile.
- Quit-and-relaunch Chrome with a flag: unnecessary since Chrome 144; wrong.
- `--categoryNetwork=false` to dodge `Network.enable`: no effect (verified).
- Blaming tab count: red herring.
- Auto-clicking Allow (AX or synthetic input): ignored / refused. Stop.
- Patching config then only `/mcp` reconnect: the loader caches config;
  `/reload-plugins` is the load-bearing step.

## Non-goals

- Never quit/relaunch the user's Chrome. Never use `--isolated` or a fresh
  `--user-data-dir`.
- Never edit `~/.claude.json` without the user's explicit yes; the doctor only
  does it under `--fix-registrations`, with a backup.
- Never attempt to approve the Allow sheet programmatically.

## Typing into pages on THIS Chrome: never use `fill` / `type_text`

The user runs the **Surfingkeys** extension (vim-style keyboard control). The
MCP's `fill` and `type_text` tools emit real keystrokes, which Surfingkeys
intercepts as commands — typing an email address navigated the tab to Account
home mid-form (2026-09-16, Cloudflare dashboard) and the form was never
submitted. Its hint overlay ("Hints to click… A S D F G") in a snapshot is the
tell.

Enter text with `evaluate_script` instead: set the value through the native
setter and dispatch `input`/`change`, then click the button from the script.
No keystrokes → nothing for Surfingkeys to grab. This also satisfies React-
controlled inputs (Paddle, Cloudflare, App Store Connect).

```js
const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
set.call(input, value);
input.dispatchEvent(new Event('input',{bubbles:true}));
input.dispatchEvent(new Event('change',{bubbles:true}));
```

## When to re-run

After any plugin update, any Chrome restart (the debug server does not
persist), or whenever a chrome-devtools tool fails. The doctor is idempotent.
