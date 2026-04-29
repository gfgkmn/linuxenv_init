---
name: chrome-mcp-attach
description: Make chrome-devtools MCP attach to the user's already-running Chrome (real profile, real tabs, real logins) instead of spawning a sandboxed automation Chrome. Use when the user asks to attach chrome MCP to their existing browser, or you observe symptoms — `list_pages` returns only `about:blank`, `Network.enable timed out`, or `ps` shows a Chrome with `--user-data-dir=...cache/chrome-devtools-mcp/chrome-profile`. Recovery procedure — must be re-run after every plugin update.
allowed-tools: Bash, Read, Edit, Write
---

# Chrome MCP — Attach to Existing Chrome (Recovery Procedure)

## What is broken (the recurring root cause)

The user's installed plugin `chrome-devtools-mcp@claude-plugins-official` ships an `.mcp.json` that does **not** pass `--autoConnect`, so the MCP defaults to spawning a sandboxed Chrome. The user's `~/.claude.json` has the correct config, but the plugin's namespaced version (`plugin:chrome-devtools-mcp:chrome-devtools`) takes precedence after `/mcp` reconnect, shadowing it.

The patch must be re-applied after every plugin auto-update because the cache directory is rewritten on update. **Do not propose moving the user to `--browser-url` + a fresh `--user-data-dir`** — they explicitly need their real profile (cookies, logins, existing tabs).

## Procedure

Run these steps in order. Stop on first failure and report.

### Step 1 — Verify the user has set up Chrome

```bash
lsof -iTCP:9222 -sTCP:LISTEN -P 2>/dev/null
```

If empty: tell the user to (a) make sure their Chrome is running, (b) navigate to `chrome://inspect/#remote-debugging` and accept the dialog. Do not proceed until 9222 is listening.

### Step 2 — Find the installed plugin's `.mcp.json` (version-agnostic)

```bash
python -c "import json; d=json.load(open('/Users/gfgkmn/.claude/plugins/installed_plugins.json')); p=d['plugins']['chrome-devtools-mcp@claude-plugins-official'][0]['installPath']; print(p+'/.mcp.json')"
```

Read the printed path. If it does not exist, plugin is not installed — the user must use the `~/.claude.json` config; tell them and stop.

### Step 3 — Check whether `--autoConnect` is present

Read the file. The args array under `mcpServers.chrome-devtools.args` should contain `"--autoConnect"`. Two known shapes have appeared in the wild:

- 0.22.0 shape:
  ```json
  { "mcpServers": { "chrome-devtools": { "command": "npx", "args": ["chrome-devtools-mcp@latest"] } } }
  ```
- 0.23.0+ shape (no `mcpServers` wrapper):
  ```json
  { "chrome-devtools": { "command": "npx", "args": ["-y", "chrome-devtools-mcp@latest", "--autoConnect"] } }
  ```

If `--autoConnect` is already in the args array — patch is unnecessary; skip to Step 5.

### Step 4 — Patch the file (Edit, append `"--autoConnect"` to args)

Use the Edit tool. Append `"--autoConnect"` as the last element in the args array. Preserve the surrounding shape (do **not** convert between the two shapes; keep what was there).

After Edit, re-read to confirm the new args array.

### Step 5 — Kill all chrome-devtools-mcp processes

```bash
pkill -f "chrome-devtools-mcp"; sleep 1
ps aux | grep chrome-devtools-mcp | grep -v grep | wc -l
```

The count should be 0. If non-zero, retry the pkill once.

### Step 6 — Tell the user to **`/reload-plugins`** (NOT `/mcp` reconnect)

This is the most important step and the one I keep getting wrong. After editing the plugin's `.mcp.json`:

- `/mcp` → Reconnect **does NOT pick up the file change**. It reattaches the session to the MCP, but the plugin loader caches the config — the new `--autoConnect` arg won't appear in the spawned process. You'll see the bug recur and falsely conclude the patch didn't work.
- **`/reload-plugins`** is what actually re-reads the plugin config from disk and respawns the MCP with the new args. Tell the user to run this.

After `/reload-plugins`, the user may also need `/mcp` to reattach the session (one extra dialog dismissal), but the config reload is the load-bearing step.

### Step 7 — Verify after reconnect

After the user confirms reconnect, call `list_pages`. Expected: their actual tabs (multiple, real URLs). Failure modes:

- Single `about:blank` only → the patch didn't take effect. Check the running process args with `ps -wwo command -p <pid>` and confirm `--autoConnect` is on the cmdline. If not, the patched file isn't the one being used — re-check Step 2's path.
- `Network.enable timed out` → either still zombies (re-run Step 5) or a frozen background tab in user's Chrome (issue #1230). Tell the user to focus a non-frozen tab.

## Why each step exists (don't shortcut)

- **Step 2 is version-agnostic** because the plugin path includes the version (e.g. `0.22.0`) which drifts over time. Hardcoding the version is what made the previous fix break silently after auto-update.
- **Step 5 (pkill) is necessary** because issue #1763 (lock-file PR #1841 still unmerged as of 2026-04-28) means stale MCPs from prior Claude Code sessions race against the new one and trigger `Network.enable` timeout even after the patch.
- **Step 6 is the most-omitted step** historically. Without it, the patch is invisible to the running session.

## Non-goals

- Do not edit `~/.claude.json`. Its `chrome-devtools` entry is already correct; the issue is the plugin shadowing it.
- Do not propose `--browser-url=http://127.0.0.1:9222` with a manually launched debug Chrome. That uses a fresh `--user-data-dir`, which loses the user's profile — they have rejected this twice.
- Do not propose uninstalling the plugin without telling the user the tradeoff: they would lose the plugin's companion skills (`chrome-devtools-mcp:memory-leak-debugging`, `:a11y-debugging`, `:debug-optimize-lcp`, `:troubleshooting`, `:chrome-devtools`, `:chrome-devtools-cli`).
