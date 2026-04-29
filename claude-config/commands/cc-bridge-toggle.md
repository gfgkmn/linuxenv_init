---
description: Toggle Emacs cc-bridge hook delegation for the current CC session
---

Toggles the bridge hook for this session.  When OFF, CC's TUI handles every permission prompt natively — Emacs stays silent (no banner, popup, or mode-line ping).  Toggling again re-enables the bridge.

This is the slash-command mirror of `M-x claude-code-bridge-toggle-session-hooks` and the CLI `cc-bridge-toggle`; all three edit the same `~/.claude/cc-bridge-disabled-uuids` file.

!`~/Applications/bin/cc-bridge-toggle 2>&1`
