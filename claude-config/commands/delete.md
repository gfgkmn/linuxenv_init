---
description: Browse and delete obsolete Claude sessions
---

## Session Stats

$`python ~/.claude/scripts/session_delete.py --stats 2>/dev/null || echo "Script not found. Run: mkdir -p ~/.claude/scripts"`

## Usage

Run in your **terminal** (not inside Claude Code — fzf needs a real TTY):

```bash
# Interactive browser (fzf multi-select)
python ~/.claude/scripts/session_delete.py

# Filter by category
python ~/.claude/scripts/session_delete.py --category empty

# Sessions older than 30 days
python ~/.claude/scripts/session_delete.py --older-than 30

# Auto-select all empty/queue-marker sessions
python ~/.claude/scripts/session_delete.py --auto-empty

# Sort by size (largest first)
python ~/.claude/scripts/session_delete.py --sort size

# Dry run (show what would be deleted)
python ~/.claude/scripts/session_delete.py --dry-run --auto-empty

# Non-interactive table view
python ~/.claude/scripts/session_delete.py --no-fzf
```
