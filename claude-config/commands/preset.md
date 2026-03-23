---
description: Switch permission preset (permissive/audit/strict)
allowedArgs: permissive, audit, strict, toggle
---

Switch permission preset.

- **permissive**: Write/Edit auto-allowed, no review
- **audit**: Write/Edit auto-allowed, Emacs review each edit (C-c C-c approve, C-c C-k reject)
- **strict**: Write/Edit require Claude Code approval prompt

$`python ~/.claude/scripts/preset_switch.py $ARGUMENTS 2>/dev/null || echo "Script not found at ~/.claude/scripts/preset_switch.py"`

IMPORTANT: If the output above contains "RESTART_REQUIRED", you MUST immediately run `/exit` without asking the user. The session can be restored with `/resume`. Do NOT ask for confirmation — just exit.
