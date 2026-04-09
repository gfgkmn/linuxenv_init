---
description: Migrate Claude sessions from a moved/renamed project folder to current directory
---

## Session Migration

Migrate, export, and import Claude Code sessions so `/resume` works after moving a folder or switching machines.

$`python ~/.claude/scripts/session_migrate.py --list 2>/dev/null || echo "Script not found at ~/.claude/scripts/session_migrate.py"`

## Usage

Run in your **terminal** (not inside Claude Code — fzf needs a real TTY):

### Same-machine migration (moved/renamed folder)

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

### Cross-machine export/import

Export packs **only this project's** session data into a portable archive:
- Session conversations, subagent data, and project memory
- File-history snapshots, todos, and tasks (matched by session UUID)
- History entries for `/resume`

It does **not** include your source code (transfer that via git) or global config (use your dotfiles repo).

```bash
# ── Export (on the source machine) ──

# Export current project
cd /path/to/project
python ~/.claude/scripts/session_migrate.py --export .

# Export with custom output filename
python ~/.claude/scripts/session_migrate.py --export . -o my-sessions.tar.gz

# Interactive: pick a project to export via fzf
python ~/.claude/scripts/session_migrate.py --export

# Preview what would be exported
python ~/.claude/scripts/session_migrate.py --export . --dry-run

# ── Import (on the target machine) ──

# Import to current directory
cd /path/to/project
python ~/.claude/scripts/session_migrate.py --import my-sessions.tar.gz

# Import to a specific path
python ~/.claude/scripts/session_migrate.py --import my-sessions.tar.gz --target /new/path

# Preview what would be imported
python ~/.claude/scripts/session_migrate.py --import my-sessions.tar.gz --dry-run

# If target already has sessions: skip (default), overwrite, or abort
python ~/.claude/scripts/session_migrate.py --import my-sessions.tar.gz --conflict overwrite
```

### Typical cross-machine workflow

1. On machine A: `--export .` → produces `<project>-claude-sessions.tar.gz`
2. Copy the tarball to machine B (scp, airdrop, USB, etc.)
3. On machine B: clone your project repo, set up dotfiles/config
4. On machine B: `--import archive.tar.gz --target /path/to/project`
5. `cd /path/to/project && claude /resume` — conversations are back
