#!/usr/bin/env python
"""Migrate, export, and import Claude Code sessions.

When you move a project directory, Claude Code can no longer find the sessions
because they're indexed by the absolute path. This script re-maps sessions
from the old path to the new path.

For cross-machine transfers, use --export to create a portable archive and
--import to unpack it on the target machine with automatic path rewriting.

Usage:
    python session_migrate.py /old/path /new/path             # migrate
    python session_migrate.py --export .                      # export cwd project
    python session_migrate.py --import archive.tar.gz         # import to cwd
    python session_migrate.py --list                          # list all projects
"""

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# ── Constants ────────────────────────────────────────────────────────────────

CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"
HISTORY_JSONL = CLAUDE_DIR / "history.jsonl"
FILE_HISTORY_DIR = CLAUDE_DIR / "file-history"
TODOS_DIR = CLAUDE_DIR / "todos"
TASKS_DIR = CLAUDE_DIR / "tasks"
EXPORT_FORMAT_VERSION = 1
EXPORT_MAGIC = "claude-session-export"

# ANSI colors
C_RESET = "\033[0m"
C_RED = "\033[31m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_CYAN = "\033[36m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"


# ── Helpers ──────────────────────────────────────────────────────────────────

def path_to_dirname(path: str) -> str:
    """Convert an absolute path to Claude's encoded directory name.

    /Users/gfgkmn/Coding/myproject -> -Users-gfgkmn-Coding-myproject
    """
    # Normalize: resolve, strip trailing slash
    p = os.path.normpath(os.path.abspath(path))
    # Replace / with -
    return p.replace("/", "-")


def dirname_to_path(dirname: str) -> str:
    """Convert Claude's encoded directory name back to an absolute path.

    -Users-gfgkmn-Coding-myproject -> /Users/gfgkmn/Coding/myproject
    """
    # The dirname starts with - which represents the leading /
    # Replace - with / to reconstruct
    return dirname.replace("-", "/")


def human_size(nbytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if abs(nbytes) < 1024:
            if unit == "B":
                return f"{nbytes}{unit}"
            return f"{nbytes:.1f}{unit}"
        nbytes /= 1024
    return f"{nbytes:.1f}TB"


def dir_total_size(path: Path) -> int:
    total = 0
    try:
        for entry in path.rglob("*"):
            if entry.is_file():
                try:
                    total += entry.stat().st_size
                except OSError:
                    pass
    except OSError:
        pass
    return total


def count_sessions(project_dir: Path) -> int:
    """Count .jsonl session files in a project directory."""
    try:
        return len(list(project_dir.glob("*.jsonl")))
    except OSError:
        return 0


def collect_session_ids(project_dir: Path) -> list[str]:
    """Extract session UUIDs from JSONL filenames in a project directory.

    Session files are named <UUID>.jsonl. Corresponding UUID directories
    (containing subagents/, tool-results/) use the same UUID.
    """
    ids = []
    try:
        for jsonl in project_dir.glob("*.jsonl"):
            stem = jsonl.stem
            # Basic UUID-like check: 8-4-4-4-12 hex pattern
            if re.match(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", stem):
                ids.append(stem)
    except OSError:
        pass
    return sorted(ids)


def collect_satellite_paths(session_ids: list[str]) -> dict[str, list[Path]]:
    """Find all satellite data (file-history, todos, tasks) for given session IDs.

    Returns dict with keys: 'file_history', 'todos', 'tasks'.
    Each value is a list of Path objects that exist on disk.
    """
    result: dict[str, list[Path]] = {"file_history": [], "todos": [], "tasks": []}

    for sid in session_ids:
        # file-history/<UUID>/
        fh_dir = FILE_HISTORY_DIR / sid
        if fh_dir.is_dir():
            result["file_history"].append(fh_dir)

        # todos/<UUID>*.json  (pattern: <UUID>-agent-<UUID>.json)
        if TODOS_DIR.exists():
            for todo_file in TODOS_DIR.glob(f"{sid}*.json"):
                result["todos"].append(todo_file)

        # tasks/<UUID>/
        task_dir = TASKS_DIR / sid
        if task_dir.is_dir():
            result["tasks"].append(task_dir)

    return result


def extract_history_entries(original_path: str) -> list[str]:
    """Extract lines from history.jsonl matching the given project path.

    Returns list of raw JSON strings (one per line).
    """
    if not HISTORY_JSONL.exists():
        return []

    matching = []
    try:
        for line in HISTORY_JSONL.read_text(errors="replace").splitlines():
            stripped = line.strip()
            if not stripped:
                continue
            try:
                entry = json.loads(stripped)
                project = entry.get("project", "")
                if project == original_path or project.startswith(original_path + "/"):
                    matching.append(stripped)
            except (json.JSONDecodeError, ValueError):
                continue
    except OSError:
        pass
    return matching


# ── List mode ────────────────────────────────────────────────────────────────

def extract_cwd_from_project(project_dir: Path) -> str:
    """Extract the actual project path from JSONL cwd fields.

    The dirname encoding is lossy (hyphens in path names are ambiguous),
    so we read the actual cwd from session data for accurate display.
    """
    for jsonl in project_dir.glob("*.jsonl"):
        try:
            with open(jsonl, "r", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        cwd = entry.get("cwd", "")
                        if cwd and os.path.isabs(cwd):
                            return cwd
                    except (json.JSONDecodeError, ValueError):
                        continue
        except OSError:
            continue
    return ""


def list_projects():
    """List all project paths that have sessions stored."""
    if not PROJECTS_DIR.exists():
        print("No projects directory found.")
        return

    projects = []
    for project_dir in sorted(PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        dirname = project_dir.name
        # Try to get actual path from session data; fall back to dirname decoding
        actual_path = extract_cwd_from_project(project_dir)
        if not actual_path:
            actual_path = dirname_to_path(dirname)
        n_sessions = count_sessions(project_dir)
        size = dir_total_size(project_dir)
        exists = os.path.isdir(actual_path)
        projects.append((actual_path, n_sessions, size, exists, dirname))

    if not projects:
        print("No project sessions found.")
        return

    # Print table
    print(f"\n{'Path':<60}  {'Sessions':>8}  {'Size':>8}  {'Exists?':>7}")
    print("─" * 90)

    missing = []
    for path, n, size, exists, dirname in projects:
        if n == 0:
            continue
        status = f"{C_GREEN}yes{C_RESET}" if exists else f"{C_RED}MISSING{C_RESET}"
        print(f"{path:<60}  {n:>8}  {human_size(size):>8}  {status}")
        if not exists:
            missing.append((path, n, dirname))

    print(f"\nTotal: {len(projects)} projects")

    if missing:
        print(f"\n{C_YELLOW}Projects with MISSING paths (candidates for migration):{C_RESET}")
        for path, n, dirname in missing:
            print(f"  {path}  ({n} sessions)")
        print(f"\nTo migrate: python {sys.argv[0]} /old/path /new/path")


# ── Migration ────────────────────────────────────────────────────────────────

def update_jsonl_cwd(jsonl_path: Path, old_path: str, new_path: str, dry_run: bool) -> int:
    """Update cwd fields in a JSONL session file. Returns count of lines updated."""
    try:
        lines = jsonl_path.read_text(errors="replace").splitlines()
    except OSError as e:
        print(f"  {C_RED}ERROR reading {jsonl_path.name}: {e}{C_RESET}")
        return 0

    updated_count = 0
    new_lines = []

    for line in lines:
        stripped = line.strip()
        if not stripped:
            new_lines.append(line)
            continue

        try:
            entry = json.loads(stripped)
        except (json.JSONDecodeError, ValueError):
            new_lines.append(line)
            continue

        changed = False

        # Update "cwd" field
        if "cwd" in entry and isinstance(entry["cwd"], str):
            if entry["cwd"] == old_path or entry["cwd"].startswith(old_path + "/"):
                entry["cwd"] = entry["cwd"].replace(old_path, new_path, 1)
                changed = True

        # Update "projectPath" field
        if "projectPath" in entry and isinstance(entry["projectPath"], str):
            if entry["projectPath"] == old_path or entry["projectPath"].startswith(old_path + "/"):
                entry["projectPath"] = entry["projectPath"].replace(old_path, new_path, 1)
                changed = True

        if changed:
            new_lines.append(json.dumps(entry, ensure_ascii=False))
            updated_count += 1
        else:
            new_lines.append(line)

    if updated_count > 0 and not dry_run:
        try:
            jsonl_path.write_text("\n".join(new_lines) + "\n" if new_lines else "")
        except OSError as e:
            print(f"  {C_RED}ERROR writing {jsonl_path.name}: {e}{C_RESET}")
            return 0

    return updated_count


def update_history_jsonl(old_path: str, new_path: str, dry_run: bool) -> int:
    """Update project paths in ~/.claude/history.jsonl (used by /resume)."""
    if not HISTORY_JSONL.exists():
        return 0

    try:
        lines = HISTORY_JSONL.read_text(errors="replace").splitlines()
    except OSError as e:
        print(f"  {C_RED}ERROR reading history.jsonl: {e}{C_RESET}")
        return 0

    updated_count = 0
    new_lines = []

    for line in lines:
        stripped = line.strip()
        if not stripped:
            new_lines.append(line)
            continue

        try:
            entry = json.loads(stripped)
        except (json.JSONDecodeError, ValueError):
            new_lines.append(line)
            continue

        changed = False

        # Update "project" field (this is what /resume uses)
        if "project" in entry and isinstance(entry["project"], str):
            if entry["project"] == old_path or entry["project"].startswith(old_path + "/"):
                entry["project"] = entry["project"].replace(old_path, new_path, 1)
                changed = True

        # Update "cwd" field if present
        if "cwd" in entry and isinstance(entry["cwd"], str):
            if entry["cwd"] == old_path or entry["cwd"].startswith(old_path + "/"):
                entry["cwd"] = entry["cwd"].replace(old_path, new_path, 1)
                changed = True

        if changed:
            new_lines.append(json.dumps(entry, ensure_ascii=False))
            updated_count += 1
        else:
            new_lines.append(line)

    if updated_count > 0 and not dry_run:
        # Backup first
        backup_path = HISTORY_JSONL.with_suffix(".jsonl.bak")
        try:
            shutil.copy2(HISTORY_JSONL, backup_path)
        except OSError:
            pass
        try:
            HISTORY_JSONL.write_text("\n".join(new_lines) + "\n" if new_lines else "")
        except OSError as e:
            print(f"  {C_RED}ERROR writing history.jsonl: {e}{C_RESET}")
            return 0

    return updated_count


def update_sessions_index(index_path: Path, old_path: str, new_path: str, dry_run: bool) -> int:
    """Update projectPath in sessions-index.json. Returns count updated."""
    if not index_path.exists():
        return 0

    try:
        data = json.loads(index_path.read_text(errors="replace"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"  {C_RED}ERROR reading sessions-index.json: {e}{C_RESET}")
        return 0

    updated = 0
    for entry in data.get("entries", []):
        pp = entry.get("projectPath", "")
        if pp == old_path or pp.startswith(old_path + "/"):
            entry["projectPath"] = pp.replace(old_path, new_path, 1)
            updated += 1

    if updated > 0 and not dry_run:
        try:
            index_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
        except OSError as e:
            print(f"  {C_RED}ERROR writing sessions-index.json: {e}{C_RESET}")
            return 0

    return updated


def migrate(old_path: str, new_path: str, dry_run: bool = False):
    """Migrate sessions from old_path to new_path."""
    # Normalize paths
    old_path = os.path.normpath(os.path.abspath(old_path))
    new_path = os.path.normpath(os.path.abspath(new_path))

    old_dirname = path_to_dirname(old_path)
    new_dirname = path_to_dirname(new_path)

    old_project_dir = PROJECTS_DIR / old_dirname
    new_project_dir = PROJECTS_DIR / new_dirname

    prefix = f"{C_YELLOW}[DRY RUN]{C_RESET} " if dry_run else ""

    print(f"\n{C_BOLD}Claude Session Migration{C_RESET}")
    print("─" * 50)
    print(f"  Old path: {old_path}")
    print(f"  New path: {new_path}")
    print(f"  Old dir:  {old_dirname}")
    print(f"  New dir:  {new_dirname}")
    print()

    # Validate
    if not old_project_dir.exists():
        print(f"{C_RED}ERROR: No sessions found for old path.{C_RESET}")
        print(f"  Expected: {old_project_dir}")
        print(f"\nUse --list to see all project paths with sessions.")
        return False

    n_sessions = count_sessions(old_project_dir)
    total_size = dir_total_size(old_project_dir)
    print(f"  Found {n_sessions} session(s), {human_size(total_size)} total")

    if new_project_dir.exists():
        n_existing = count_sessions(new_project_dir)
        if n_existing > 0:
            print(f"\n{C_YELLOW}WARNING: Target already has {n_existing} session(s).{C_RESET}")
            print("  Sessions will be merged (no overwrites of existing files).")

    print()

    if not dry_run:
        try:
            answer = input(f"Proceed with migration? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\nCancelled.")
            return False
        if answer not in ("y", "yes"):
            print("Cancelled.")
            return False

    # Step 1: Ensure target directory exists
    if not dry_run:
        new_project_dir.mkdir(parents=True, exist_ok=True)

    # Step 2: Move/merge files from old to new
    files_moved = 0
    jsonl_updated = 0

    for item in sorted(old_project_dir.iterdir()):
        target = new_project_dir / item.name

        if target.exists():
            print(f"  {C_DIM}SKIP (exists): {item.name}{C_RESET}")
            continue

        if not dry_run:
            shutil.move(str(item), str(target))

        print(f"  {prefix}MOVE: {item.name}")
        files_moved += 1

    # Step 3: Update cwd/projectPath inside JSONL files
    print(f"\n{prefix}Updating paths in session files...")
    for jsonl in sorted(new_project_dir.glob("*.jsonl")):
        n = update_jsonl_cwd(jsonl, old_path, new_path, dry_run)
        if n > 0:
            print(f"  {prefix}{jsonl.name}: {n} entries updated")
            jsonl_updated += n

    # Step 4: Update sessions-index.json
    index_path = new_project_dir / "sessions-index.json"
    n_idx = update_sessions_index(index_path, old_path, new_path, dry_run)
    if n_idx > 0:
        print(f"  {prefix}sessions-index.json: {n_idx} entries updated")

    # Step 5: Update ~/.claude/history.jsonl (critical for /resume)
    print(f"\n{prefix}Updating history.jsonl...")
    n_hist = update_history_jsonl(old_path, new_path, dry_run)
    if n_hist > 0:
        print(f"  {prefix}history.jsonl: {n_hist} entries updated")
    else:
        print(f"  No matching entries in history.jsonl")

    # Step 6: Clean up empty old directory
    if not dry_run:
        try:
            remaining = list(old_project_dir.iterdir())
            if not remaining:
                old_project_dir.rmdir()
                print(f"\n  Removed empty old directory: {old_dirname}")
            else:
                print(f"\n  {C_YELLOW}Old directory not empty ({len(remaining)} items remain): {old_dirname}{C_RESET}")
        except OSError:
            pass

    # Summary
    print(f"\n{C_GREEN}{'[DRY RUN] ' if dry_run else ''}Migration complete!{C_RESET}")
    print(f"  Files moved:    {files_moved}")
    print(f"  Paths updated:  {jsonl_updated}")
    if n_idx:
        print(f"  Index entries:  {n_idx}")
    print(f"  History entries: {n_hist}")
    print(f"\nYou can now resume sessions with: cd {new_path} && claude /resume")

    return True


# ── Export / Import ─────────────────────────────────────────────────────────

def export_project(project_path: str, output_file: str | None, dry_run: bool = False) -> bool:
    """Export a project's complete session data to a portable archive."""
    project_path = os.path.normpath(os.path.abspath(project_path))
    encoded = path_to_dirname(project_path)
    project_dir = PROJECTS_DIR / encoded

    prefix = f"{C_YELLOW}[DRY RUN]{C_RESET} " if dry_run else ""

    print(f"\n{C_BOLD}Claude Session Export{C_RESET}")
    print("─" * 50)
    print(f"  Project: {project_path}")

    if not project_dir.exists():
        # Try finding by cwd in session data (handles lossy encoding)
        for candidate in PROJECTS_DIR.iterdir():
            if candidate.is_dir() and extract_cwd_from_project(candidate) == project_path:
                project_dir = candidate
                encoded = candidate.name
                break
        else:
            print(f"\n{C_RED}ERROR: No sessions found for this project.{C_RESET}")
            print(f"  Looked for: {project_dir}")
            print(f"\nUse --list to see all project paths with sessions.")
            return False

    # Discover session IDs and satellite data
    session_ids = collect_session_ids(project_dir)
    n_sessions = count_sessions(project_dir)
    satellites = collect_satellite_paths(session_ids)
    history_entries = extract_history_entries(project_path)
    project_size = dir_total_size(project_dir)

    # Compute satellite sizes
    fh_size = sum(dir_total_size(p) for p in satellites["file_history"])
    todo_size = sum(p.stat().st_size for p in satellites["todos"] if p.exists())
    task_size = sum(dir_total_size(p) for p in satellites["tasks"])

    total_size = project_size + fh_size + todo_size + task_size

    print(f"  Sessions: {n_sessions} ({human_size(project_size)})")
    if satellites["file_history"]:
        print(f"  File history: {len(satellites['file_history'])} session(s) ({human_size(fh_size)})")
    if satellites["todos"]:
        print(f"  Todos: {len(satellites['todos'])} file(s) ({human_size(todo_size)})")
    if satellites["tasks"]:
        print(f"  Tasks: {len(satellites['tasks'])} session(s) ({human_size(task_size)})")
    print(f"  History entries: {len(history_entries)}")

    # Check for memory directory
    memory_dir = project_dir / "memory"
    has_memory = memory_dir.is_dir() and any(memory_dir.iterdir())
    if has_memory:
        print(f"  Memory: {C_GREEN}yes{C_RESET}")

    print(f"  Total: ~{human_size(total_size)}")

    if dry_run:
        print(f"\n{C_YELLOW}[DRY RUN] No archive created.{C_RESET}")
        return True

    # Determine output filename
    if not output_file:
        basename = os.path.basename(project_path) or "project"
        output_file = f"{basename}-claude-sessions.tar.gz"
    output_path = os.path.abspath(output_file)

    # Build archive in a temp directory
    with tempfile.TemporaryDirectory() as tmpdir:
        export_root = Path(tmpdir) / "claude-session-export"
        export_root.mkdir()

        # Write manifest
        manifest = {
            "version": EXPORT_FORMAT_VERSION,
            "format": EXPORT_MAGIC,
            "created": datetime.now(timezone.utc).isoformat(),
            "original_path": project_path,
            "encoded_dirname": encoded,
            "hostname": socket.gethostname(),
            "session_ids": session_ids,
            "session_count": n_sessions,
            "has_memory": has_memory,
            "has_file_history": len(satellites["file_history"]) > 0,
            "has_todos": len(satellites["todos"]) > 0,
            "has_tasks": len(satellites["tasks"]) > 0,
            "total_size_bytes": total_size,
        }
        (export_root / "manifest.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False)
        )

        # Copy project directory contents
        projects_dest = export_root / "projects"
        shutil.copytree(project_dir, projects_dest)

        # Copy satellite data
        if satellites["file_history"]:
            fh_dest = export_root / "file-history"
            fh_dest.mkdir()
            for fh_dir in satellites["file_history"]:
                shutil.copytree(fh_dir, fh_dest / fh_dir.name)

        if satellites["todos"]:
            todos_dest = export_root / "todos"
            todos_dest.mkdir()
            for todo_file in satellites["todos"]:
                shutil.copy2(todo_file, todos_dest / todo_file.name)

        if satellites["tasks"]:
            tasks_dest = export_root / "tasks"
            tasks_dest.mkdir()
            for task_dir in satellites["tasks"]:
                shutil.copytree(task_dir, tasks_dest / task_dir.name)

        # Write history entries
        if history_entries:
            (export_root / "history-entries.jsonl").write_text(
                "\n".join(history_entries) + "\n"
            )

        # Create tar.gz
        with tarfile.open(output_path, "w:gz") as tar:
            tar.add(str(export_root), arcname="claude-session-export")

    archive_size = os.path.getsize(output_path)
    print(f"\n{C_GREEN}Export complete!{C_RESET}")
    print(f"  Archive: {output_path}")
    print(f"  Size: {human_size(archive_size)} (compressed)")
    print(f"\nTo import on another machine:")
    print(f"  python session_migrate.py --import {os.path.basename(output_path)} --target /path/to/project")

    return True


def import_project(
    archive_path: str, target_path: str, dry_run: bool = False, conflict: str = "skip"
) -> bool:
    """Import sessions from an archive into a target project path."""
    archive_path = os.path.abspath(archive_path)
    target_path = os.path.normpath(os.path.abspath(target_path))

    prefix = f"{C_YELLOW}[DRY RUN]{C_RESET} " if dry_run else ""

    if not os.path.isfile(archive_path):
        print(f"{C_RED}ERROR: Archive not found: {archive_path}{C_RESET}")
        return False

    print(f"\n{C_BOLD}Claude Session Import{C_RESET}")
    print("─" * 50)

    # Extract to temp directory and read manifest
    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(archive_path, "r:gz") as tar:
                tar.extractall(tmpdir)
        except (tarfile.TarError, OSError) as e:
            print(f"{C_RED}ERROR: Failed to extract archive: {e}{C_RESET}")
            return False

        export_root = Path(tmpdir) / "claude-session-export"
        manifest_path = export_root / "manifest.json"

        if not manifest_path.exists():
            print(f"{C_RED}ERROR: Invalid archive — no manifest.json found.{C_RESET}")
            return False

        try:
            manifest = json.loads(manifest_path.read_text())
        except (json.JSONDecodeError, OSError) as e:
            print(f"{C_RED}ERROR: Failed to read manifest: {e}{C_RESET}")
            return False

        if manifest.get("format") != EXPORT_MAGIC:
            print(f"{C_RED}ERROR: Not a Claude session export archive.{C_RESET}")
            return False

        original_path = manifest["original_path"]
        session_ids = manifest.get("session_ids", [])
        old_encoded = manifest.get("encoded_dirname", path_to_dirname(original_path))
        new_encoded = path_to_dirname(target_path)
        new_project_dir = PROJECTS_DIR / new_encoded

        print(f"  From: {original_path} ({manifest.get('hostname', '?')})")
        print(f"  To:   {target_path}")
        print(f"  Sessions: {manifest.get('session_count', '?')}")
        if manifest.get("has_memory"):
            print(f"  Memory: {C_GREEN}included{C_RESET}")
        if manifest.get("has_file_history"):
            print(f"  File history: included")
        if manifest.get("has_todos"):
            print(f"  Todos: included")
        if manifest.get("has_tasks"):
            print(f"  Tasks: included")
        print()

        # Conflict detection
        if new_project_dir.exists():
            n_existing = count_sessions(new_project_dir)
            if n_existing > 0:
                if conflict == "abort":
                    print(f"{C_RED}ERROR: Target already has {n_existing} session(s). "
                          f"Use --conflict skip or --conflict overwrite.{C_RESET}")
                    return False
                elif conflict == "skip":
                    print(f"{C_YELLOW}Target has {n_existing} existing session(s) — "
                          f"existing files will be skipped.{C_RESET}")
                elif conflict == "overwrite":
                    print(f"{C_YELLOW}Target has {n_existing} existing session(s) — "
                          f"existing files will be overwritten.{C_RESET}")

        if dry_run:
            print(f"\n{C_YELLOW}[DRY RUN] No changes made.{C_RESET}")
            return True

        if not dry_run:
            try:
                answer = input(f"Proceed with import? [y/N] ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                print("\nCancelled.")
                return False
            if answer not in ("y", "yes"):
                print("Cancelled.")
                return False

        # Step 1: Copy project files
        new_project_dir.mkdir(parents=True, exist_ok=True)
        src_projects = export_root / "projects"
        files_copied = 0

        if src_projects.is_dir():
            for item in sorted(src_projects.rglob("*")):
                rel = item.relative_to(src_projects)
                dest = new_project_dir / rel
                if item.is_dir():
                    dest.mkdir(parents=True, exist_ok=True)
                elif item.is_file():
                    if dest.exists() and conflict == "skip":
                        print(f"  {C_DIM}SKIP (exists): {rel}{C_RESET}")
                        continue
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(item, dest)
                    files_copied += 1

        # Step 2: Rewrite paths in session JSONL files
        jsonl_updated = 0
        print(f"\n{prefix}Rewriting paths in session files...")
        for jsonl in sorted(new_project_dir.glob("*.jsonl")):
            n = update_jsonl_cwd(jsonl, original_path, target_path, dry_run=False)
            if n > 0:
                print(f"  {jsonl.name}: {n} entries updated")
                jsonl_updated += n

        # Step 3: Rewrite sessions-index.json
        index_path = new_project_dir / "sessions-index.json"
        n_idx = update_sessions_index(index_path, original_path, target_path, dry_run=False)
        if n_idx > 0:
            print(f"  sessions-index.json: {n_idx} entries updated")

        # Also rewrite fullPath and originalPath in sessions-index.json
        if index_path.exists():
            try:
                data = json.loads(index_path.read_text(errors="replace"))
                changed = False
                for entry in data.get("entries", []):
                    fp = entry.get("fullPath", "")
                    if fp:
                        # Rebuild fullPath using local PROJECTS_DIR
                        basename = os.path.basename(fp)
                        entry["fullPath"] = str(new_project_dir / basename)
                        changed = True
                if "originalPath" in data:
                    data["originalPath"] = target_path
                    changed = True
                if changed:
                    index_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
                    print(f"  sessions-index.json: fullPath/originalPath rebuilt")
            except (json.JSONDecodeError, OSError) as e:
                print(f"  {C_YELLOW}WARNING: Could not update fullPath: {e}{C_RESET}")

        # Step 4: Copy satellite data (UUIDs are stable, no path rewriting needed)
        src_fh = export_root / "file-history"
        if src_fh.is_dir():
            fh_count = 0
            for fh_dir in src_fh.iterdir():
                if fh_dir.is_dir():
                    dest = FILE_HISTORY_DIR / fh_dir.name
                    if dest.exists() and conflict == "skip":
                        continue
                    FILE_HISTORY_DIR.mkdir(parents=True, exist_ok=True)
                    if dest.exists():
                        shutil.rmtree(dest)
                    shutil.copytree(fh_dir, dest)
                    fh_count += 1
            if fh_count:
                print(f"  File history: {fh_count} session(s) copied")

        src_todos = export_root / "todos"
        if src_todos.is_dir():
            todo_count = 0
            TODOS_DIR.mkdir(parents=True, exist_ok=True)
            for todo_file in src_todos.iterdir():
                if todo_file.is_file():
                    dest = TODOS_DIR / todo_file.name
                    if dest.exists() and conflict == "skip":
                        continue
                    shutil.copy2(todo_file, dest)
                    todo_count += 1
            if todo_count:
                print(f"  Todos: {todo_count} file(s) copied")

        src_tasks = export_root / "tasks"
        if src_tasks.is_dir():
            task_count = 0
            for task_dir in src_tasks.iterdir():
                if task_dir.is_dir():
                    dest = TASKS_DIR / task_dir.name
                    if dest.exists() and conflict == "skip":
                        continue
                    TASKS_DIR.mkdir(parents=True, exist_ok=True)
                    if dest.exists():
                        shutil.rmtree(dest)
                    shutil.copytree(task_dir, dest)
                    task_count += 1
            if task_count:
                print(f"  Tasks: {task_count} session(s) copied")

        # Step 5: Merge history entries with path rewriting
        src_history = export_root / "history-entries.jsonl"
        if src_history.exists():
            new_entries = []
            for line in src_history.read_text(errors="replace").splitlines():
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    entry = json.loads(stripped)
                    if "project" in entry and isinstance(entry["project"], str):
                        entry["project"] = entry["project"].replace(original_path, target_path, 1)
                    if "cwd" in entry and isinstance(entry["cwd"], str):
                        entry["cwd"] = entry["cwd"].replace(original_path, target_path, 1)
                    new_entries.append(json.dumps(entry, ensure_ascii=False))
                except (json.JSONDecodeError, ValueError):
                    new_entries.append(stripped)

            if new_entries:
                # Backup history first
                if HISTORY_JSONL.exists():
                    backup = HISTORY_JSONL.with_suffix(".jsonl.bak")
                    try:
                        shutil.copy2(HISTORY_JSONL, backup)
                    except OSError:
                        pass
                with open(HISTORY_JSONL, "a") as f:
                    f.write("\n".join(new_entries) + "\n")
                print(f"  History: {len(new_entries)} entries merged")

    # Summary
    print(f"\n{C_GREEN}Import complete!{C_RESET}")
    print(f"  Files copied:   {files_copied}")
    print(f"  Paths rewritten: {jsonl_updated}")
    print(f"\nYou can now resume sessions with: cd {target_path} && claude /resume")

    return True


# ── Interactive source selector ──────────────────────────────────────────────

def collect_missing_projects() -> list[tuple[str, int, int, str]]:
    """Collect projects whose paths no longer exist.

    Returns list of (actual_path, n_sessions, total_size, dirname).
    """
    if not PROJECTS_DIR.exists():
        return []

    missing = []
    for project_dir in sorted(PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        dirname = project_dir.name
        actual_path = extract_cwd_from_project(project_dir)
        if not actual_path:
            actual_path = dirname_to_path(dirname)
        n_sessions = count_sessions(project_dir)
        if n_sessions == 0:
            continue
        if not os.path.isdir(actual_path):
            size = dir_total_size(project_dir)
            missing.append((actual_path, n_sessions, size, dirname))
    return missing


def collect_all_projects() -> list[tuple[str, int, int, str, bool]]:
    """Collect all projects with sessions.

    Returns list of (actual_path, n_sessions, total_size, dirname, exists).
    """
    if not PROJECTS_DIR.exists():
        return []

    projects = []
    for project_dir in sorted(PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        dirname = project_dir.name
        actual_path = extract_cwd_from_project(project_dir)
        if not actual_path:
            actual_path = dirname_to_path(dirname)
        n_sessions = count_sessions(project_dir)
        if n_sessions == 0:
            continue
        size = dir_total_size(project_dir)
        exists = os.path.isdir(actual_path)
        projects.append((actual_path, n_sessions, size, dirname, exists))
    return projects


def select_source_fzf(
    target_path: str | None = None,
    show_all: bool = False,
    header_prefix: str = "Select source project to migrate INTO",
) -> str | None:
    """Use fzf to select a source project.

    By default only shows MISSING projects. Use show_all=True to show all.
    header_prefix customizes the picker header (e.g. for export vs migrate).
    """
    if show_all:
        projects = collect_all_projects()
        # Exclude the target itself
        if target_path:
            projects = [(p, n, s, d, e) for p, n, s, d, e in projects
                        if os.path.normpath(p) != os.path.normpath(target_path)]
    else:
        projects = collect_missing_projects()

    if not projects:
        if show_all:
            print(f"{C_YELLOW}No other projects with sessions found.{C_RESET}")
        else:
            print(f"{C_YELLOW}No projects with missing paths found.{C_RESET}")
            print(f"Use --all to show all projects (not just missing ones).")
        return None

    # Build fzf lines
    fzf_lines = []
    for item in projects:
        if show_all:
            path, n, size, dirname, exists = item
            status = f"{C_GREEN}EXISTS{C_RESET}" if exists else f"{C_RED}MISSING{C_RESET}"
        else:
            path, n, size, dirname = item
            status = f"{C_RED}MISSING{C_RESET}"

        line = f"{path:<60}  {n:>3} sessions  {human_size(size):>8}  {status}"
        fzf_lines.append(line)

    fzf_input = "\n".join(fzf_lines)

    header_target = f": {target_path}" if target_path else ""
    header = (
        f"{header_prefix}{header_target}\n"
        f"{'Path':<60}  {'Sessions':>12}  {'Size':>8}  Status"
    )

    cmd = [
        "fzf",
        "--ansi",
        "--reverse",
        "--header", header,
        "--no-multi",
    ]

    if not sys.stdin.isatty():
        return select_source_fallback(projects, target_path, show_all)

    try:
        result = subprocess.run(cmd, input=fzf_input, capture_output=True, text=True)
    except FileNotFoundError:
        # Fallback without fzf
        return select_source_fallback(projects, target_path, show_all)

    if result.returncode != 0:
        return None

    # Extract path from selected line (everything before the first big gap of spaces)
    selected = result.stdout.strip()
    if not selected:
        return None

    # Strip ANSI and parse — path is the first column (up to the session count)
    raw = re.sub(r"\033\[[0-9;]*m", "", selected).strip()
    # Path ends before the session count pattern "  N sessions"
    match = re.match(r"^(.+?)\s{2,}\d+\s+sessions", raw)
    if match:
        return match.group(1).strip()

    return None


def select_source_fallback(
    projects: list, target_path: str, show_all: bool
) -> str | None:
    """Numbered-list fallback when fzf is unavailable."""
    print(f"\n{C_BOLD}Select source project to migrate INTO: {target_path}{C_RESET}\n")
    print(f"{'#':<4}  {'Path':<55}  {'Sessions':>8}  {'Size':>8}  Status")
    print("─" * 95)

    for i, item in enumerate(projects, 1):
        if show_all:
            path, n, size, dirname, exists = item
            status = "EXISTS" if exists else "MISSING"
        else:
            path, n, size, dirname = item
            status = "MISSING"
        print(f"{i:<4}  {path:<55}  {n:>8}  {human_size(size):>8}  {status}")

    print()
    try:
        raw = input("Enter number (or 'q' to quit): ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return None

    if raw.lower() in ("q", "quit", ""):
        return None

    try:
        idx = int(raw)
        if 1 <= idx <= len(projects):
            return projects[idx - 1][0]
    except ValueError:
        pass

    print(f"{C_RED}Invalid selection.{C_RESET}")
    return None


# ── CLI ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Migrate, export, and import Claude Code sessions.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Migrate (same machine, moved folder)
  %(prog)s --list                          # Show all projects and find missing paths
  %(prog)s /old/path /new/path --dry-run   # Preview what would change
  %(prog)s /old/path /new/path             # Perform the migration
  %(prog)s --here                          # Interactive: pick source, migrate to cwd
  %(prog)s --here --all                    # Show all projects (not just missing)

  # Export (pack sessions for transfer to another machine)
  %(prog)s --export .                      # Export current directory's sessions
  %(prog)s --export /path/to/project       # Export specific project
  %(prog)s --export                        # Interactive: pick project via fzf
  %(prog)s --export . -o backup.tar.gz     # Custom output filename
  %(prog)s --export . --dry-run            # Preview what would be exported

  # Import (unpack sessions on a new machine)
  %(prog)s --import archive.tar.gz                     # Import to cwd
  %(prog)s --import archive.tar.gz --target /new/path  # Import to specific path
  %(prog)s --import archive.tar.gz --dry-run           # Preview import
  %(prog)s --import archive.tar.gz --conflict overwrite
        """,
    )
    parser.add_argument(
        "old_path", nargs="?", default=None,
        help="Original absolute path of the project",
    )
    parser.add_argument(
        "new_path", nargs="?", default=None,
        help="New absolute path of the project",
    )
    parser.add_argument(
        "--list", action="store_true",
        help="List all project paths with sessions (highlights missing paths)",
    )
    parser.add_argument(
        "--here", action="store_true",
        help="Interactive mode: use current directory as target, pick source via fzf",
    )
    parser.add_argument(
        "--all", action="store_true",
        help="With --here/--export: show all projects, not just missing ones",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be done without making changes",
    )
    parser.add_argument(
        "--export", metavar="PATH", nargs="?", const="__PICKER__", default=None,
        help="Export project sessions to a portable archive. "
             "Pass a project path, '.' for cwd, or omit for fzf picker.",
    )
    parser.add_argument(
        "--import", dest="import_archive", metavar="ARCHIVE", default=None,
        help="Import sessions from a .tar.gz archive",
    )
    parser.add_argument(
        "--target", metavar="PATH", default=None,
        help="Target project path for --import (defaults to cwd)",
    )
    parser.add_argument(
        "-o", "--output", metavar="FILE", default=None,
        help="Output filename for --export (defaults to <project>-claude-sessions.tar.gz)",
    )
    parser.add_argument(
        "--conflict", choices=["skip", "overwrite", "abort"], default="skip",
        help="Conflict resolution for --import when sessions already exist (default: skip)",
    )

    args = parser.parse_args()

    if args.list:
        list_projects()
        return

    # ── Export mode ──
    if args.export is not None:
        if args.export == "__PICKER__":
            source = select_source_fzf(
                target_path=None, show_all=True,
                header_prefix="Select project to export",
            )
            if not source:
                print("No project selected. Cancelled.")
                return
            project_path = source
        else:
            project_path = os.path.normpath(os.path.abspath(args.export))
        export_project(project_path, args.output, dry_run=args.dry_run)
        return

    # ── Import mode ──
    if args.import_archive:
        target = args.target or os.getcwd()
        target = os.path.normpath(os.path.abspath(target))
        import_project(
            args.import_archive, target,
            dry_run=args.dry_run, conflict=args.conflict,
        )
        return

    # ── Interactive migrate mode ──
    if args.here:
        target = os.path.normpath(os.path.abspath(os.getcwd()))
        print(f"{C_BOLD}Target (current directory):{C_RESET} {target}\n")
        source = select_source_fzf(target, show_all=args.all)
        if not source:
            print("No source selected. Cancelled.")
            return
        migrate(source, target, dry_run=args.dry_run)
        return

    # ── Explicit path migrate mode ──
    if not args.old_path or not args.new_path:
        parser.print_help()
        print(f"\n{C_YELLOW}Tip: Use --here for interactive mode, or --list to browse.{C_RESET}")
        sys.exit(1)

    migrate(args.old_path, args.new_path, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
