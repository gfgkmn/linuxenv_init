---
description: Toggle the cc-bridge global kill-switch (all hooks across all sessions)
---

Flips the bridge's global kill-switch.  When ON, `cc-bridge-hook.sh` short-circuits EVERY event across EVERY session — no Emacs side effects from any CC at all.  When OFF (default), hooks deliver normally.

State is persisted as the presence of `~/.claude/cc-bridge-disabled-globally`; the CLI, slash command, and `M-x claude-code-bridge-toggle-bridge-globally` all touch / delete the same file.

!`~/Applications/bin/cc-bridge-toggle-globally 2>&1`
