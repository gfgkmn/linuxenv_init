---
description: Migrate Claude sessions from a moved/renamed project folder to current directory
---

## Session Migration

Migrate sessions from a previous project path to the current directory, so `/resume` works after moving a folder.

$`python ~/.claude/scripts/session_migrate.py --list 2>/dev/null || echo "Script not found at ~/.claude/scripts/session_migrate.py"`

## Usage

Run in your **terminal** (not inside Claude Code — fzf needs a real TTY):

```bash
# Interactive: pick a source project, migrate to current directory
cd /new/project/path
python ~/.claude/scripts/session_migrate.py --here

# Show all projects (not just missing ones)
python ~/.claude/scripts/session_migrate.py --here --all

# Explicit old/new paths
python ~/.claude/scripts/session_migrate.py /old/path /new/path

# Dry run first
python ~/.claude/scripts/session_migrate.py --here --dry-run

# List all projects and find missing paths
python ~/.claude/scripts/session_migrate.py --list
```
