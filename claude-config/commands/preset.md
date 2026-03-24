---
description: Switch audit preset (permissive/audit/strict) — session-scoped
allowedArgs: permissive, audit, strict, toggle
---

Switch audit preset for this session.

- **permissive**: Allow all edits, no review
- **audit**: Emacs review each edit (C-c C-c approve, C-c C-k reject)
- **strict**: Terminal prompt per edit (y=allow, n=reject with reason, a=allow all, e=open in Emacs)

$`python ~/.claude/scripts/preset_switch.py $ARGUMENTS 2>/dev/null || echo "Script not found"`

IMPORTANT: If the output above contains "CLAUDE_AUDIT_MODE=", you MUST set that environment variable for this session by running a Bash command: `export CLAUDE_AUDIT_MODE=<value>`. Extract the value from the output line. This is critical — the preset won't take effect without it.
