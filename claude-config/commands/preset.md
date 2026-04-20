---
description: Switch audit preset (permissive/audit) — project-scoped, immediate
allowedArgs: permissive, audit, toggle
---

Switch audit preset for this project. Active immediately, no restart needed.

- **permissive**: Allow all edits, no review
- **audit**: Emacs review each edit (C-c C-c approve, C-c C-k reject)

!`python ~/.claude/scripts/preset_switch.py $ARGUMENTS 2>&1 || echo "Script not found"`
