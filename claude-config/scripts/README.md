# Claude Code Session Manager

An interactive tool to browse, inspect, and bulk-delete Claude Code sessions that accumulate in `~/.claude/projects/`.

## The Problem

Claude Code stores every session as `.jsonl` files under `~/.claude/projects/<project>/`. Over time, these accumulate — many are empty queue-markers, short test sessions, or obsolete conversations. There's no built-in way to browse or clean them up.

This tool gives you a visual, interactive way to see all your sessions, inspect their contents, and selectively delete the ones you don't need.

## Files

| File | Purpose |
|------|---------|
| `~/.claude/scripts/session_delete.py` | Main interactive script (Python 3, ~440 lines) |
| `~/.claude/commands/delete.md` | `/delete` command for use inside Claude Code |

## Requirements

- **Python 3.10+** (uses `match` on `dataclass`, type hints with `list[]`)
- **fzf** (optional but recommended) — for interactive multi-select with preview
- **macOS** — uses `/usr/bin/trash` for safe deletion (moves to Trash, not permanent delete). Falls back to `shutil.rmtree` / `unlink` on other systems.

## Quick Start

```bash
# Run the interactive browser
python ~/.claude/scripts/session_delete.py
```

This opens fzf with all your sessions listed. Use it like this:

1. **Scroll** through the list (arrow keys or type to filter)
2. **Preview** any session (shown in the right pane automatically)
3. **Select** sessions for deletion with `TAB`
4. **Confirm** with `ENTER`
5. Review the confirmation prompt, then type `y` to proceed

## How Sessions Are Displayed

Each line in the browser shows:

```
ID        Project         Date         Size    Msgs  Cat     Description
702ea603  Temp            01/31 19:02  10.8M  32msg  normal  WordPress to Ghost CMS migration...
c9f585a3  Temp            02/06 18:42   139B   0msg  empty   [queue-marker]
```

| Column | Description |
|--------|-------------|
| **ID** | First 8 characters of the session UUID |
| **Project** | Derived from the project directory path |
| **Date** | Last modified date (MM/DD HH:MM) |
| **Size** | Total size including `.jsonl` file + companion subdirectory |
| **Msgs** | Message count (conversation turns) |
| **Cat** | Category classification (see below) |
| **Description** | Session summary, last user message, or first prompt |

### Session Categories

Sessions are automatically classified into four categories:

| Category | Criteria | Color (fzf) |
|----------|----------|-------------|
| **empty** | No real messages (only queue-operations/file-history-snapshots), or < 500 bytes | Red |
| **tiny** | 5 or fewer messages AND < 5KB total | Yellow |
| **normal** | Regular sessions that don't fit other categories | Default |
| **large** | Total size >= 1MB (including subagent data) | Cyan |

Additionally, sessions modified within the last 60 seconds are tagged `[ACTIVE]` in green and are automatically skipped during deletion.

## Preview Pane

When browsing with fzf, the right pane shows detailed information for the highlighted session:

- Full session UUID and project path
- Git branch (if any)
- Category, indexed status, creation/modification dates
- JSONL file size and total size (including subdirectories)
- Message type breakdown (user, assistant, system, progress, etc.)
- Session summary (from `sessions-index.json` if available)
- First prompt text
- Up to 20 user messages with their content

## CLI Reference

```
usage: session_delete.py [-h] [--project PROJECT] [--category {empty,tiny,normal,large}]
                         [--older-than DAYS] [--sort {date,size,msgs}] [--dry-run]
                         [--no-fzf] [--preview SESSION_ID] [--auto-empty] [--stats]
```

### Options

| Flag | Description | Example |
|------|-------------|---------|
| `--stats` | Print summary statistics only (no interactive UI) | `--stats` |
| `--no-fzf` | Print a static table to stdout (no interactivity) | `--no-fzf` |
| `--project NAME` | Filter to sessions whose project name contains NAME (case-insensitive) | `--project hapi` |
| `--category CAT` | Show only sessions of this category | `--category empty` |
| `--older-than DAYS` | Show only sessions last modified more than N days ago | `--older-than 30` |
| `--sort {date,size,msgs}` | Sort order. Default: `date` (newest first) | `--sort size` |
| `--auto-empty` | Skip fzf, auto-select all `empty` sessions for deletion | `--auto-empty` |
| `--dry-run` | Show what would be deleted without actually deleting | `--dry-run` |
| `--preview ID` | Internal: used by fzf to render the preview pane | (not for manual use) |

### Common Workflows

**See how much space sessions are using:**
```bash
python ~/.claude/scripts/session_delete.py --stats
```
```
Claude Sessions Summary
────────────────────────────────────────
  Total sessions:  79
  Total size:      34.2MB
  Projects:        13
────────────────────────────────────────
  empty      28 sessions    17.1KB
  tiny       17 sessions    35.4KB
  normal     25 sessions     6.4MB
  large       9 sessions    27.8MB
  Session-env: 49 dirs
```

**Browse everything interactively:**
```bash
python ~/.claude/scripts/session_delete.py
```

**Clean up all empty queue-marker sessions:**
```bash
# Preview first
python ~/.claude/scripts/session_delete.py --dry-run --auto-empty

# Then delete
python ~/.claude/scripts/session_delete.py --auto-empty
```

**Delete old sessions from a specific project:**
```bash
python ~/.claude/scripts/session_delete.py --project Temp --older-than 14
```

**Find the largest sessions:**
```bash
python ~/.claude/scripts/session_delete.py --no-fzf --sort size
```

**Delete tiny test sessions:**
```bash
python ~/.claude/scripts/session_delete.py --category tiny
```

## fzf Keybindings

| Key | Action |
|-----|--------|
| `TAB` | Toggle selection on current item |
| `Shift+TAB` | Toggle selection and move up |
| `Ctrl+A` | Select all visible items |
| `Ctrl+D` | Deselect all |
| `ENTER` | Confirm selection and proceed to deletion |
| `ESC` / `Ctrl+C` | Cancel and exit |
| Arrow keys / typing | Navigate and filter the list |

## What Gets Deleted

When you confirm deletion, the following are removed for each selected session:

1. **`.jsonl` file** — the session transcript (`~/.claude/projects/<project>/<uuid>.jsonl`)
2. **Companion UUID directory** — subagent data and tool results (`~/.claude/projects/<project>/<uuid>/`)
3. **Session environment directory** — if it exists (`~/.claude/session-env/<uuid>/`)
4. **Index entry** — removed from the project's `sessions-index.json`

All file deletions go through macOS `/usr/bin/trash`, so deleted files can be recovered from the system Trash if needed.

## Fallback Mode (No fzf)

If fzf is not installed, the script automatically falls back to a numbered list:

```
ID    Session     Project         Date            Size    Msgs  Cat     Description
────────────────────────────────────────────────────────────────────────────────────────────
1     702ea603    Temp            01/31 19:02    10.8M   32msg  normal  WordPress to Ghost...
2     c9f585a3    Temp            02/06 18:42     139B    0msg  empty   [queue-marker]
3     48763511    Temp            02/24 15:26     1.4M   73msg  large   write a interactive...

Enter numbers to delete (e.g. 1,3,5-8) or 'q' to quit:
```

You can enter individual numbers, comma-separated lists, or ranges (e.g., `1,3,5-8`).

## Using `/delete` Inside Claude Code

Inside a Claude Code session, type `/delete` to see a quick summary and usage instructions. The actual deletion must be run from your terminal since fzf requires a real TTY.

## How It Works

### Data Sources

The script reads from two data sources per project:

1. **`sessions-index.json`** — contains rich metadata (summary, firstPrompt, messageCount, timestamps, gitBranch) for sessions that Claude Code has indexed. Not all sessions are indexed.

2. **`.jsonl` files** — the raw session transcripts. Each line is a JSON object with fields like `type` (user, assistant, system, progress, queue-operation, file-history-snapshot), `message`, `timestamp`, etc.

### Performance Optimizations

- **Seek-based reading**: For `.jsonl` files larger than 50KB, only the first 50 and last 50 lines are read (using file seeking), which is sufficient to extract metadata without loading multi-megabyte transcripts.
- **Full reads for preview**: The preview pane reads the complete file to show all user messages, but only when you highlight a specific session.
- **Indexed session shortcut**: For sessions that have entries in `sessions-index.json`, most metadata is read directly from the index without parsing the JSONL.

### Safety Measures

- **Active session protection**: Sessions modified within the last 60 seconds are marked `[ACTIVE]` and automatically skipped during deletion, even if selected.
- **Trash-based deletion**: Files are moved to macOS Trash via `/usr/bin/trash`, not permanently deleted. You can recover them from `~/.Trash/` if needed.
- **Confirmation prompt**: Every deletion (except `--dry-run`) requires explicit `y` confirmation after showing exactly what will be deleted.
- **Dry-run mode**: Use `--dry-run` with any workflow to preview the effect without changing anything.
- **Project directories preserved**: Empty project directories are left intact after deletion (they may contain `memory/` or other important data).
