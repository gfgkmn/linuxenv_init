---
description: Migrate Claude sessions from a moved/renamed project folder to current directory
---

## Session Migration

Migrate, export, and import Claude Code sessions so `/resume` works after moving a folder or switching machines.

Parse the user's arguments from `$ARGUMENTS` and dispatch the appropriate subcommand below. If no arguments or `help`, show the help section.

### Subcommands

#### `help` (or no arguments)

Show this help overview, then run `--list` to give the user context:

$`python ~/.claude/scripts/session_migrate.py --list 2>/dev/null || echo "Script not found at ~/.claude/scripts/session_migrate.py"`

Then display the subcommand reference:

```
/migrate                  Show this help + project overview
/migrate list             List all projects (path, sessions, size, missing?)
/migrate sessions         List sessions in current project (UUIDs, sizes, topics)
/migrate restore <UUID>   Register a session so `claude --resume` can find it
/migrate repair           Audit & auto-fix current project (orphaned sessions, stale paths)
/migrate repair --dry-run Preview what repair would fix
/migrate export           Export current project sessions to .tar.gz
/migrate import <file>    Import sessions from a .tar.gz archive

For interactive commands (fzf picker, migrate between paths):
  Run in your terminal:  python ~/.claude/scripts/session_migrate.py --help
```

#### `list`

Run `python ~/.claude/scripts/session_migrate.py --list` and display the output.
This shows all projects with session counts, sizes, and highlights MISSING paths that need migration.

#### `sessions` or `sessions <path>`

If a path argument is given, use that. Otherwise default to `.` (current project).
Run `python ~/.claude/scripts/session_migrate.py --sessions <path>` and display the output.
This shows every session with its UUID, last-modified date, size, history status, and first user message.

After showing the output, remind the user:
- To restore a session: `/migrate restore <UUID>`
- To batch-fix all orphaned sessions: `/migrate repair`

#### `restore <UUID>`

Extract the UUID from the arguments.
Run `python ~/.claude/scripts/session_migrate.py --resume-id <UUID>` and display the output.
After success, remind the user they can now run `claude --resume` to pick up that session.

#### `repair` or `repair --dry-run`

Check if `--dry-run` is in the arguments.
Run `python ~/.claude/scripts/session_migrate.py --repair . [--dry-run]` and display the output.
This audits the current project for:
- Orphaned sessions (file exists but not in history.jsonl)
- Ghost history entries (in history but no session file)
- Stale cwd paths inside session files

Without `--dry-run`, it fixes orphaned and stale-path issues automatically.

#### `export` or `export <path>`

If a path argument is given, use that. Otherwise default to `.` (current project).
Run `python ~/.claude/scripts/session_migrate.py --export <path>` and display the output.

Note: this runs non-interactively (no confirmation prompt needed for export). The archive is written to the current directory.

After success, show the user what was created and how to import on another machine.

#### `import <file>` or `import <file> <target_path>`

This command requires interactive confirmation (y/N prompt), so it must run in tmux.
Extract the archive path and optional target path from arguments.
Run in tmux: `python ~/.claude/scripts/session_migrate.py --import <file> [--target <target_path>]`

If no file argument is given, show usage:
```
Usage: /migrate import <archive.tar.gz> [target_path]
  archive.tar.gz  — the export file created by /migrate export
  target_path     — where to import (defaults to current directory)
```

#### `here` or any migration with old/new paths

These need fzf or interactive input. Tell the user to run in their terminal:
```
# Interactive (pick source via fzf, migrate to current directory):
python ~/.claude/scripts/session_migrate.py --here

# Explicit paths:
python ~/.claude/scripts/session_migrate.py /old/path /new/path

# Preview first:
python ~/.claude/scripts/session_migrate.py /old/path /new/path --dry-run
```

### Important notes

- All commands that call the script should run via tmux (`bash ~/.claude/scripts/tmux-exec.sh`) since the script may take time to scan session files.
- For `--list`, `--sessions`, `--repair`, `--resume-id`, and `--export`: these do NOT need interactive input and can run directly.
- For `--import` and `--here`: these prompt for confirmation and need tmux or a real terminal.
- Always show the script output to the user — don't summarize or hide it.
