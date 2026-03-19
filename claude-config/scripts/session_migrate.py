#!/usr/bin/env python
"""Migrate Claude Code sessions after moving a project folder.

When you move a project directory, Claude Code can no longer find the sessions
because they're indexed by the absolute path. This script re-maps sessions
from the old path to the new path.

Usage:
    python session_migrate.py /old/path/to/project /new/path/to/project
    python session_migrate.py /old/path /new/path --dry-run
    python session_migrate.py --list   # show all project paths with sessions
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# ── Constants ────────────────────────────────────────────────────────────────

CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"
HISTORY_JSONL = CLAUDE_DIR / "history.jsonl"

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


def select_source_fzf(target_path: str, show_all: bool = False) -> str | None:
    """Use fzf to select a source project to migrate from.

    By default only shows MISSING projects. Use show_all=True to show all.
    """
    if show_all:
        projects = collect_all_projects()
        # Exclude the target itself
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

    header = (
        f"Select source project to migrate INTO: {target_path}\n"
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
        description="Migrate Claude Code sessions after moving a project folder.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --list                          # Show all projects and find missing paths
  %(prog)s /old/path /new/path --dry-run   # Preview what would change
  %(prog)s /old/path /new/path             # Perform the migration
  %(prog)s --here                          # Interactive: pick source, migrate to cwd
  %(prog)s --here --all                    # Show all projects (not just missing)
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
        help="With --here: show all projects, not just missing ones",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be done without making changes",
    )

    args = parser.parse_args()

    if args.list:
        list_projects()
        return

    if args.here:
        target = os.path.normpath(os.path.abspath(os.getcwd()))
        print(f"{C_BOLD}Target (current directory):{C_RESET} {target}\n")
        source = select_source_fzf(target, show_all=args.all)
        if not source:
            print("No source selected. Cancelled.")
            return
        migrate(source, target, dry_run=args.dry_run)
        return

    if not args.old_path or not args.new_path:
        parser.print_help()
        print(f"\n{C_YELLOW}Tip: Use --here for interactive mode, or --list to browse.{C_RESET}")
        sys.exit(1)

    migrate(args.old_path, args.new_path, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
