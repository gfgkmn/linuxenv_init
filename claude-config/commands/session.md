---
description: Unified Claude Code session management — browse, delete, rename, search, migrate, export, import, repair
allowedArgs: list, sessions, stats, delete, rename, search, resume, repair, export, import, migrate, help
---

## Session Management

Unified interface for all Claude Code session operations. Parse the user's arguments from `$ARGUMENTS` and dispatch the appropriate subcommand below. If no arguments or `help`, show the help section.

### Subcommands

#### `help` (or no arguments)

Show the overview — run `stats` first to give context:

!`python ~/.claude/scripts/session.py stats 2>&1 || echo "Script not found at ~/.claude/scripts/session.py"`

Then display the subcommand reference:

```
/session                       Show this help + stats overview
/session list                  All projects (path, sessions, size, missing?)
/session sessions [PATH]       Sessions in a project (UUIDs, dates, topics) — default: cwd
/session stats                 Summary statistics
/session delete [filters]      Delete sessions (interactive)
/session rename <UUID> "TITLE" Set a session's custom title
/session search <query>        Search all sessions for a user prompt
/session resume <UUID>         Register session so `claude --resume` can find it
/session repair [--dry-run]    Audit & fix orphaned sessions, stale paths (cwd)
/session export [PATH]         Pack sessions into .tar.gz
/session import <archive>      Unpack archive & rewrite paths

Shortcut: /search <query>      Same as /session search

For interactive commands (fzf browser, migrate between paths):
  Run in your terminal:  python ~/.claude/scripts/session.py --help
```

#### `list`

Run `python ~/.claude/scripts/session.py list` and display the output.
Shows all projects with session counts, sizes, and highlights MISSING paths that need migration.

#### `sessions` or `sessions <path>`

If a path argument is given, use that. Otherwise default to `.` (current project).
Run `python ~/.claude/scripts/session.py sessions <path>` and display the output.
Shows every session with UUID, last-modified date, size, history status, and first user message.

After showing the output, remind:
- To restore a session: `/session resume <UUID>`
- To batch-fix orphaned sessions: `/session repair`

#### `stats`

Run `python ~/.claude/scripts/session.py stats` and display the output.

#### `delete`

Deletion is interactive (fzf multi-select + y/N confirmation). Tell the user to run in their terminal:

```
python ~/.claude/scripts/session.py              # or: /session browse
python ~/.claude/scripts/session.py delete --category empty --auto-empty
python ~/.claude/scripts/session.py delete --older-than 30
```

Non-interactive table view (safe to run here):
`python ~/.claude/scripts/session.py table` — show output.

#### `rename <UUID> "<TITLE>"`

Extract UUID and title from arguments.
Run `python ~/.claude/scripts/session.py rename <UUID> "<TITLE>"` and display output.

If no UUID, show usage:
```
Usage: /session rename <UUID-prefix> "<new title>"
Tip: get UUIDs from /session sessions
```

#### `search <query>`

Search requires an fzf picker so it must run in tmux or the user's terminal.
If no arguments, show usage.
Otherwise, tell the user to run:
```
python ~/.claude/scripts/session.py search "$ARGUMENTS"
```

Or use `/search $ARGUMENTS` — same thing with shorter syntax.

#### `resume <UUID>`

Extract UUID from arguments.
Run `python ~/.claude/scripts/session.py resume <UUID>` and display output.
After success, remind the user they can now run `claude --resume` to pick up that session.

#### `repair` or `repair --dry-run`

Check if `--dry-run` is in the arguments.
Run `python ~/.claude/scripts/session.py repair . [--dry-run]` and display output.
Audits the current project for:
- Orphaned sessions (file exists but not in history.jsonl)
- Ghost history entries (in history but no session file)
- Stale cwd paths inside session files

Without `--dry-run`, fixes orphaned and stale-path issues automatically.

#### `export` or `export <path>`

If a path argument is given, use that. Otherwise default to `.` (current project).
Run `python ~/.claude/scripts/session.py export <path>` and display output.
The archive is written to the current directory.

After success, show the user what was created and how to import on another machine.

#### `import <file>` or `import <file> <target_path>`

Requires interactive confirmation (y/N prompt), so must run in tmux.
Extract archive path and optional target from arguments.
Run in tmux: `python ~/.claude/scripts/session.py import <file> [--target <target_path>]`

If no file argument given, show usage:
```
Usage: /session import <archive.tar.gz> [target_path]
  archive.tar.gz  — file created by /session export
  target_path     — where to import (defaults to current directory)
```

#### `migrate` or `migrate <old> <new>`

Needs fzf or interactive input. Tell the user to run in their terminal:

```
# Interactive (pick source via fzf, migrate to current directory):
python ~/.claude/scripts/session.py migrate --here

# Explicit paths:
python ~/.claude/scripts/session.py migrate /old/path /new/path

# Preview first:
python ~/.claude/scripts/session.py migrate /old/path /new/path --dry-run
```

### Important notes

- All commands should run via tmux (`bash ~/.claude/scripts/tmux-exec.sh`) since the script may take time to scan session files.
- Safe to run directly (no TTY needed): `list`, `sessions`, `stats`, `table`, `rename`, `resume`, `repair`, `export`.
- Need tmux / real terminal: `delete` (fzf), `search` (fzf), `migrate --here` (fzf), `import` (y/N prompt).
- Always show the script output to the user — don't summarize or hide it.
