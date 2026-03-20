---
description: Switch permission preset (strict/permissive)
allowedArgs: strict, permissive, toggle
---

Switch permission preset. Strict disables auto-allowed Write/Edit/MultiEdit; permissive re-enables them.

$`python ~/.claude/scripts/preset_switch.py $ARGUMENTS 2>/dev/null || echo "Script not found at ~/.claude/scripts/preset_switch.py"`
