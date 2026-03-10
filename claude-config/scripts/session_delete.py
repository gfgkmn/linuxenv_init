#!/usr/bin/env python
"""Interactive Claude Code session browser and deleter.

Browse, inspect, and bulk-delete sessions via fzf multi-select.
Falls back to a numbered list if fzf is unavailable.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


# ── Constants ────────────────────────────────────────────────────────────────

CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"
SESSION_ENV_DIR = CLAUDE_DIR / "session-env"
ACTIVE_THRESHOLD_SECS = 60  # files modified within this window are [ACTIVE]
LARGE_FILE_THRESHOLD = 50 * 1024  # 50KB - use seek optimization
LARGE_SESSION_THRESHOLD = 1 * 1024 * 1024  # 1MB
TINY_MSG_THRESHOLD = 5
TINY_SIZE_THRESHOLD = 5 * 1024  # 5KB
EMPTY_SIZE_THRESHOLD = 500  # bytes

SKIP_USER_MESSAGES = frozenset({
    "/quit", "/exit", "/status", "/help", "/clear",
    "[Request interrupted by user for tool use]",
    "[Request interrupted by user]",
})

# Patterns to strip from display text
import re

# System/auto-generated tag blocks to strip entirely (tag + content)
SYSTEM_BLOCK_TAGS = (
    "local-command-caveat", "system-reminder", "command-message",
    "command-name", "user-prompt-submit-hook", "environment_details",
    "claude_code_context", "antml:thinking", "fast_mode_info",
)
_block_pattern = "|".join(re.escape(t) for t in SYSTEM_BLOCK_TAGS)
SYSTEM_BLOCK_RE = re.compile(
    rf"<({_block_pattern})\b[^>]*>[\s\S]*?</\1>",
    re.DOTALL,
)
TAG_RE = re.compile(r"<[^>]+>")
ANSI_RE = re.compile(r"\033\[[0-9;]*m")

# ANSI color codes
C_RESET = "\033[0m"
C_RED = "\033[31m"
C_YELLOW = "\033[33m"
C_CYAN = "\033[36m"
C_GREEN = "\033[32m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"


# ── Data Layer ───────────────────────────────────────────────────────────────

@dataclass
class SessionInfo:
    session_id: str
    project_name: str
    jsonl_path: Path
    has_subdir: bool = False
    subdir_path: Optional[Path] = None
    total_size_bytes: int = 0
    modified: float = 0.0
    created: float = 0.0
    message_count: int = 0
    summary: str = ""
    first_prompt: str = ""
    last_message: str = ""
    is_indexed: bool = False
    category: str = "normal"  # empty, tiny, normal, large
    git_branch: str = ""
    project_path: str = ""
    is_active: bool = False
    user_messages: list = field(default_factory=list)
    msg_type_counts: dict = field(default_factory=dict)


def dir_size(path: Path) -> int:
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


def clean_display_text(text: str) -> str:
    """Strip system tag blocks and remaining XML tags, clean text for display."""
    # First strip entire system/auto-generated blocks (tag + content)
    text = SYSTEM_BLOCK_RE.sub("", text)
    # Then strip any remaining standalone tags
    text = TAG_RE.sub("", text)
    # Collapse whitespace
    text = " ".join(text.split())
    return text.strip()


def extract_text_from_content(content) -> str:
    """Extract plain text from message content (string or content blocks)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text":
                    parts.append(block.get("text", ""))
                elif block.get("type") == "tool_result":
                    # skip tool results
                    pass
            elif isinstance(block, str):
                parts.append(block)
        return " ".join(parts)
    return ""


def parse_jsonl_lines(lines: list[str], collect_user_msgs: bool = False) -> dict:
    """Parse JSONL lines and extract session metadata."""
    info = {
        "message_count": 0,
        "user_messages": [],
        "last_message": "",
        "first_prompt": "",
        "created": None,
        "modified": None,
        "git_branch": "",
        "project_path": "",
        "msg_type_counts": {},
        "has_real_content": False,
    }

    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue

        entry_type = entry.get("type", "")
        info["msg_type_counts"][entry_type] = info["msg_type_counts"].get(entry_type, 0) + 1

        ts_str = entry.get("timestamp")
        if ts_str:
            try:
                ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00")).timestamp()
                if info["created"] is None or ts < info["created"]:
                    info["created"] = ts
                if info["modified"] is None or ts > info["modified"]:
                    info["modified"] = ts
            except (ValueError, TypeError):
                pass

        if entry_type in ("queue-operation", "file-history-snapshot"):
            continue

        info["has_real_content"] = True
        info["message_count"] += 1

        if entry.get("git_branch") or entry.get("gitBranch"):
            info["git_branch"] = entry.get("gitBranch", entry.get("git_branch", ""))
        if entry.get("cwd"):
            info["project_path"] = entry.get("cwd", "")

        msg = entry.get("message", {})
        if not isinstance(msg, dict):
            continue
        role = msg.get("role", "")
        if entry_type == "user" and role == "user":
            text = extract_text_from_content(msg.get("content", ""))
            text = text.strip()
            if text and text not in SKIP_USER_MESSAGES:
                if not info["first_prompt"]:
                    info["first_prompt"] = text
                info["last_message"] = text
                if collect_user_msgs:
                    info["user_messages"].append(text)

    return info


def read_file_smart(path: Path) -> list[str]:
    """Read a JSONL file, using seek optimization for large files."""
    size = path.stat().st_size
    if size <= LARGE_FILE_THRESHOLD:
        try:
            return path.read_text(errors="replace").splitlines()
        except OSError:
            return []

    # For large files: read first 50 + last 50 lines
    lines = []
    try:
        with open(path, "r", errors="replace") as f:
            for i, line in enumerate(f):
                if i >= 50:
                    break
                lines.append(line)

            # Seek to get tail
            f.seek(0, 2)
            file_size = f.tell()
            # Read last ~100KB for tail lines
            seek_pos = max(0, file_size - 100 * 1024)
            f.seek(seek_pos)
            if seek_pos > 0:
                f.readline()  # skip partial line
            tail = f.readlines()
            tail = tail[-50:]
            lines.extend(tail)
    except OSError:
        pass
    return lines


def read_file_full(path: Path) -> list[str]:
    """Read full file contents (for preview)."""
    try:
        return path.read_text(errors="replace").splitlines()
    except OSError:
        return []


def scan_projects() -> list[SessionInfo]:
    """Scan all projects and collect session info."""
    if not PROJECTS_DIR.exists():
        return []

    sessions = []
    now = time.time()

    for project_dir in sorted(PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue

        project_name = project_dir.name
        # Make readable: -Users-fhqgqj-Coding-foo -> Coding/foo
        readable = project_name.replace("-Users-fhqgqj-", "").replace("-", "/")
        if not readable:
            readable = project_name

        # Load index if available
        index_data = {}
        index_path = project_dir / "sessions-index.json"
        if index_path.exists():
            try:
                idx = json.loads(index_path.read_text(errors="replace"))
                for entry in idx.get("entries", []):
                    sid = entry.get("sessionId", "")
                    if sid:
                        index_data[sid] = entry
            except (json.JSONDecodeError, OSError):
                pass

        # Scan JSONL files (top-level only)
        for jsonl in sorted(project_dir.glob("*.jsonl")):
            session_id = jsonl.stem
            si = SessionInfo(
                session_id=session_id,
                project_name=readable,
                jsonl_path=jsonl,
            )

            # File stats
            try:
                stat = jsonl.stat()
                si.total_size_bytes = stat.st_size
                si.modified = stat.st_mtime
                si.created = stat.st_ctime
            except OSError:
                continue

            # Companion UUID directory
            subdir = project_dir / session_id
            if subdir.is_dir():
                si.has_subdir = True
                si.subdir_path = subdir
                si.total_size_bytes += dir_size(subdir)

            # Active check
            si.is_active = (now - si.modified) < ACTIVE_THRESHOLD_SECS

            # Indexed session
            if session_id in index_data:
                idx_entry = index_data[session_id]
                si.is_indexed = True
                si.summary = idx_entry.get("summary", "")
                si.first_prompt = idx_entry.get("firstPrompt", "")
                si.message_count = idx_entry.get("messageCount", 0)
                si.git_branch = idx_entry.get("gitBranch", "")
                si.project_path = idx_entry.get("projectPath", "")
                created_str = idx_entry.get("created", "")
                modified_str = idx_entry.get("modified", "")
                try:
                    if created_str:
                        si.created = datetime.fromisoformat(
                            created_str.replace("Z", "+00:00")
                        ).timestamp()
                    if modified_str:
                        si.modified = datetime.fromisoformat(
                            modified_str.replace("Z", "+00:00")
                        ).timestamp()
                except (ValueError, TypeError):
                    pass

                # Still need last_message from file
                lines = read_file_smart(jsonl)
                parsed = parse_jsonl_lines(lines)
                si.last_message = parsed["last_message"]
                si.msg_type_counts = parsed["msg_type_counts"]
            else:
                # Parse from JSONL
                lines = read_file_smart(jsonl)
                parsed = parse_jsonl_lines(lines)
                si.message_count = parsed["message_count"]
                si.first_prompt = parsed["first_prompt"]
                si.last_message = parsed["last_message"]
                si.git_branch = parsed["git_branch"]
                si.project_path = parsed["project_path"]
                si.msg_type_counts = parsed["msg_type_counts"]
                if parsed["created"]:
                    si.created = parsed["created"]
                if parsed["modified"]:
                    si.modified = parsed["modified"]

            # Classify
            si.category = classify_session(si)
            sessions.append(si)

    return sessions


def classify_session(si: SessionInfo) -> str:
    """Classify session into empty/tiny/normal/large."""
    has_real = si.message_count > 0 or bool(si.first_prompt) or bool(si.last_message)
    if not has_real and si.total_size_bytes < EMPTY_SIZE_THRESHOLD:
        return "empty"
    if not has_real:
        # has some data but no real messages (queue ops, file snapshots only)
        return "empty"
    if si.message_count <= TINY_MSG_THRESHOLD and si.total_size_bytes < TINY_SIZE_THRESHOLD:
        return "tiny"
    if si.total_size_bytes >= LARGE_SESSION_THRESHOLD:
        return "large"
    return "normal"


# ── Display Layer ────────────────────────────────────────────────────────────

def human_size(nbytes: int) -> str:
    """Format bytes as human-readable string."""
    for unit in ("B", "KB", "MB", "GB"):
        if abs(nbytes) < 1024:
            if unit == "B":
                return f"{nbytes}{unit}"
            return f"{nbytes:.1f}{unit}"
        nbytes /= 1024
    return f"{nbytes:.1f}TB"


def format_date(ts: float) -> str:
    """Format timestamp as MM/DD HH:MM."""
    if ts <= 0:
        return "??/?? ??:??"
    dt = datetime.fromtimestamp(ts)
    return dt.strftime("%m/%d %H:%M")


def truncate(text: str, width: int) -> str:
    """Truncate text to width, adding ellipsis if needed."""
    text = text.replace("\n", " ").replace("\r", "").replace("\t", " ")
    if len(text) <= width:
        return text
    return text[: width - 3] + "..."


def category_color(cat: str, active: bool = False) -> str:
    if active:
        return C_GREEN + C_BOLD
    return {
        "empty": C_RED,
        "tiny": C_YELLOW,
        "normal": "",
        "large": C_CYAN,
    }.get(cat, "")


def format_fzf_line(si: SessionInfo) -> str:
    """Format a session as a single fzf-selectable line."""
    color = category_color(si.category, si.is_active)
    reset = C_RESET if color else ""

    active_tag = " [ACTIVE]" if si.is_active else ""
    desc = si.summary or si.last_message or si.first_prompt or "[queue-marker]"
    desc = clean_display_text(desc)
    desc = truncate(desc, 60)

    sid_short = si.session_id[:8]
    project = truncate(si.project_name, 14)
    date = format_date(si.modified)
    size = human_size(si.total_size_bytes).rjust(6)
    msgs = f"{si.message_count}msg".rjust(6)
    cat = si.category.ljust(6)

    line = (
        f"{color}{sid_short}  {project:<14s}  {date}  {size}  {msgs}  "
        f"{cat}  {desc}{active_tag}{reset}"
    )
    return line


def format_table_line(si: SessionInfo) -> str:
    """Format for --no-fzf tabular output (no ANSI)."""
    desc = si.summary or si.last_message or si.first_prompt or "[queue-marker]"
    desc = clean_display_text(desc)
    desc = truncate(desc, 50)
    sid_short = si.session_id[:8]
    project = truncate(si.project_name, 14)
    date = format_date(si.modified)
    size = human_size(si.total_size_bytes).rjust(6)
    msgs = f"{si.message_count}msg".rjust(6)
    cat = si.category.ljust(6)
    active = " [ACTIVE]" if si.is_active else ""
    return (
        f"{sid_short}  {project:<14s}  {date}  {size}  {msgs}  "
        f"{cat}  {desc}{active}"
    )


def format_preview(si: SessionInfo) -> str:
    """Format detailed preview for fzf preview pane."""
    lines = []
    lines.append(f"{'═' * 50}")
    lines.append(f"Session: {si.session_id}")
    lines.append(f"Project: {si.project_name}")
    if si.project_path:
        lines.append(f"Path:    {si.project_path}")
    if si.git_branch:
        lines.append(f"Branch:  {si.git_branch}")
    lines.append(f"{'─' * 50}")
    lines.append(f"Category: {si.category.upper()}" + (" [ACTIVE]" if si.is_active else ""))
    lines.append(f"Indexed:  {'yes' if si.is_indexed else 'no'}")
    lines.append(f"Created:  {format_date(si.created)}")
    lines.append(f"Modified: {format_date(si.modified)}")
    lines.append(f"JSONL:    {human_size(si.jsonl_path.stat().st_size) if si.jsonl_path.exists() else '?'}")
    lines.append(f"Total:    {human_size(si.total_size_bytes)}")
    if si.has_subdir:
        lines.append(f"Subdir:   yes ({si.subdir_path})")
    lines.append(f"Messages: {si.message_count}")

    if si.msg_type_counts:
        lines.append(f"{'─' * 50}")
        lines.append("Message types:")
        for k, v in sorted(si.msg_type_counts.items()):
            lines.append(f"  {k}: {v}")

    if si.summary:
        lines.append(f"{'─' * 50}")
        lines.append(f"Summary: {si.summary}")

    # Load full user messages for preview
    full_lines = read_file_full(si.jsonl_path)
    parsed = parse_jsonl_lines(full_lines, collect_user_msgs=True)
    user_msgs = [clean_display_text(m) for m in parsed["user_messages"]]
    user_msgs = [m for m in user_msgs if m]  # drop msgs that were purely system tags

    first = clean_display_text(si.first_prompt) if si.first_prompt else ""
    if first:
        lines.append(f"{'─' * 50}")
        lines.append(f"First prompt: {truncate(first, 200)}")

    if user_msgs:
        lines.append(f"{'─' * 50}")
        lines.append(f"User messages ({len(user_msgs)} total):")
        for i, msg in enumerate(user_msgs[:20]):
            lines.append(f"  [{i + 1}] {truncate(msg, 120)}")
        if len(user_msgs) > 20:
            lines.append(f"  ... and {len(user_msgs) - 20} more")

    lines.append(f"{'═' * 50}")
    return "\n".join(lines)


# ── fzf Layer ────────────────────────────────────────────────────────────────

def run_fzf(sessions: list[SessionInfo]) -> list[SessionInfo]:
    """Run fzf multi-select and return chosen sessions."""
    if not sessions:
        print("No sessions to display.")
        return []

    # Build id->session map
    sid_map = {si.session_id: si for si in sessions}

    # Build fzf input
    fzf_lines = []
    for si in sessions:
        fzf_lines.append(format_fzf_line(si))

    fzf_input = "\n".join(fzf_lines)

    script_path = os.path.abspath(__file__)
    header = (
        "TAB=select  ENTER=confirm  ctrl-a=all  ctrl-d=deselect  ESC=cancel\n"
        "ID        Project         Date         Size    Msgs  Cat     Description"
    )

    cmd = [
        "fzf",
        "--multi",
        "--ansi",
        "--reverse",
        "--header", header,
        "--preview", f"python {script_path} --preview {{1}}",
        "--preview-window", "right:50%:wrap",
        "--bind", "ctrl-a:select-all,ctrl-d:deselect-all",
    ]

    try:
        result = subprocess.run(
            cmd,
            input=fzf_input,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        print("fzf not found. Falling back to numbered list.")
        return fallback_select(sessions)

    if result.returncode != 0:
        # User cancelled
        return []

    # Parse selected lines - first 8 chars of each line is session_id prefix
    selected = []
    for line in result.stdout.strip().splitlines():
        # Strip ANSI codes to get raw text
        raw = strip_ansi(line).strip()
        if not raw:
            continue
        sid_prefix = raw[:8].strip()
        # Find matching session
        for sid, si in sid_map.items():
            if sid.startswith(sid_prefix):
                selected.append(si)
                break

    return selected


def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes from text."""
    return ANSI_RE.sub("", text)


def fallback_select(sessions: list[SessionInfo]) -> list[SessionInfo]:
    """Numbered-list fallback when fzf is unavailable."""
    print(f"\n{'ID':<4}  {'Session':<10}  {'Project':<14}  {'Date':<12}  {'Size':>6}  "
          f"{'Msgs':>6}  {'Cat':<6}  Description")
    print("─" * 100)

    for i, si in enumerate(sessions, 1):
        desc = si.summary or si.last_message or si.first_prompt or "[queue-marker]"
        desc = clean_display_text(desc)
        desc = truncate(desc, 40)
        active = " [ACTIVE]" if si.is_active else ""
        print(
            f"{i:<4}  {si.session_id[:8]:<10}  {truncate(si.project_name, 14):<14}  "
            f"{format_date(si.modified):<12}  {human_size(si.total_size_bytes):>6}  "
            f"{si.message_count:>4}msg  {si.category:<6}  {desc}{active}"
        )

    print()
    try:
        raw = input("Enter numbers to delete (e.g. 1,3,5-8) or 'q' to quit: ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return []

    if raw.lower() in ("q", "quit", ""):
        return []

    indices = parse_range_input(raw)
    selected = []
    for idx in indices:
        if 1 <= idx <= len(sessions):
            selected.append(sessions[idx - 1])
    return selected


def parse_range_input(raw: str) -> list[int]:
    """Parse input like '1,3,5-8' into a list of integers."""
    result = []
    for part in raw.split(","):
        part = part.strip()
        if "-" in part:
            try:
                start, end = part.split("-", 1)
                result.extend(range(int(start), int(end) + 1))
            except ValueError:
                pass
        else:
            try:
                result.append(int(part))
            except ValueError:
                pass
    return sorted(set(result))


# ── Deletion Layer ───────────────────────────────────────────────────────────

def confirm_deletion(sessions: list[SessionInfo], dry_run: bool = False) -> bool:
    """Show confirmation table and prompt user."""
    total_bytes = sum(si.total_size_bytes for si in sessions)
    prefix = "[DRY RUN] " if dry_run else ""

    print(f"\n{prefix}About to delete {len(sessions)} session(s) "
          f"(total {human_size(total_bytes)}):\n")

    for si in sessions:
        active = " [ACTIVE!]" if si.is_active else ""
        desc = si.summary or si.last_message or si.first_prompt or "[queue-marker]"
        desc = clean_display_text(desc)
        desc = truncate(desc, 45)
        print(
            f"  {si.session_id[:8]}  {truncate(si.project_name, 14):<14}  "
            f"{human_size(si.total_size_bytes):>6}  {si.category:<6}  {desc}{active}"
        )

    # Warn about active sessions
    active = [si for si in sessions if si.is_active]
    if active:
        print(f"\n  ⚠  {len(active)} session(s) marked [ACTIVE] — may be in use!")

    print()
    if dry_run:
        print(f"{prefix}Would delete the above sessions.")
        return False

    try:
        answer = input("Proceed? [y/N] ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        return False

    return answer in ("y", "yes")


def delete_sessions(sessions: list[SessionInfo], dry_run: bool = False) -> dict:
    """Delete selected sessions. Returns stats dict."""
    stats = {"deleted": 0, "failed": 0, "bytes_freed": 0, "details": []}

    for si in sessions:
        if si.is_active:
            print(f"  SKIP {si.session_id[:8]}: active session")
            stats["details"].append((si.session_id[:8], "skipped (active)"))
            continue

        success = True

        # 1. Trash the JSONL file
        if si.jsonl_path.exists():
            if not dry_run:
                ok = trash_path(si.jsonl_path)
                if not ok:
                    success = False

        # 2. Trash companion UUID directory
        if si.has_subdir and si.subdir_path and si.subdir_path.exists():
            if not dry_run:
                ok = trash_path(si.subdir_path)
                if not ok:
                    success = False

        # 3. Trash session-env directory
        env_dir = SESSION_ENV_DIR / si.session_id
        if env_dir.exists():
            if not dry_run:
                ok = trash_path(env_dir)
                if not ok:
                    success = False

        # 4. Remove from sessions-index.json
        if si.is_indexed and not dry_run:
            cleanup_index(si)

        if success:
            stats["deleted"] += 1
            stats["bytes_freed"] += si.total_size_bytes
            stats["details"].append((si.session_id[:8], "deleted"))
        else:
            stats["failed"] += 1
            stats["details"].append((si.session_id[:8], "FAILED"))

    return stats


def trash_path(path: Path) -> bool:
    """Move a path to trash using macOS trash command."""
    try:
        subprocess.run(
            ["/usr/bin/trash", str(path)],
            capture_output=True,
            check=True,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback: try to remove directly
        try:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
            return True
        except OSError as e:
            print(f"  ERROR trashing {path}: {e}")
            return False


def cleanup_index(si: SessionInfo) -> None:
    """Remove a session entry from the project's sessions-index.json."""
    # Reconstruct project dir path from jsonl_path
    project_dir = si.jsonl_path.parent
    index_path = project_dir / "sessions-index.json"
    if not index_path.exists():
        return

    try:
        data = json.loads(index_path.read_text(errors="replace"))
        entries = data.get("entries", [])
        data["entries"] = [e for e in entries if e.get("sessionId") != si.session_id]
        index_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    except (json.JSONDecodeError, OSError) as e:
        print(f"  WARN: could not update index for {si.session_id[:8]}: {e}")


# ── Stats ────────────────────────────────────────────────────────────────────

def print_stats(sessions: list[SessionInfo]) -> None:
    """Print summary statistics."""
    if not sessions:
        print("No sessions found.")
        return

    total_size = sum(si.total_size_bytes for si in sessions)
    cats = {}
    for si in sessions:
        cats.setdefault(si.category, []).append(si)

    projects = set(si.project_name for si in sessions)

    print(f"Claude Sessions Summary")
    print(f"{'─' * 40}")
    print(f"  Total sessions:  {len(sessions)}")
    print(f"  Total size:      {human_size(total_size)}")
    print(f"  Projects:        {len(projects)}")
    print(f"{'─' * 40}")

    for cat in ("empty", "tiny", "normal", "large"):
        items = cats.get(cat, [])
        if items:
            cat_size = sum(si.total_size_bytes for si in items)
            print(f"  {cat:<8} {len(items):>4} sessions  {human_size(cat_size):>8}")

    active = [si for si in sessions if si.is_active]
    if active:
        print(f"{'─' * 40}")
        print(f"  Active now:  {len(active)}")

    # Session-env dirs
    env_count = 0
    if SESSION_ENV_DIR.exists():
        try:
            env_count = len(list(SESSION_ENV_DIR.iterdir()))
        except OSError:
            pass
    if env_count:
        print(f"  Session-env: {env_count} dirs")


# ── CLI Layer ────────────────────────────────────────────────────────────────

def apply_filters(sessions: list[SessionInfo], args) -> list[SessionInfo]:
    """Apply CLI filters to session list."""
    result = sessions

    if args.project:
        pat = args.project.lower()
        result = [si for si in result if pat in si.project_name.lower()]

    if args.category:
        result = [si for si in result if si.category == args.category]

    if args.older_than is not None:
        cutoff = time.time() - (args.older_than * 86400)
        result = [si for si in result if si.modified < cutoff]

    # Sort
    if args.sort == "size":
        result.sort(key=lambda s: s.total_size_bytes, reverse=True)
    elif args.sort == "msgs":
        result.sort(key=lambda s: s.message_count, reverse=True)
    else:  # date (default)
        result.sort(key=lambda s: s.modified, reverse=True)

    return result


def handle_preview(session_id_prefix: str, sessions: list[SessionInfo]) -> None:
    """Handle --preview callback from fzf."""
    for si in sessions:
        if si.session_id.startswith(session_id_prefix):
            print(format_preview(si))
            return
    print(f"Session {session_id_prefix} not found.")


def main():
    parser = argparse.ArgumentParser(
        description="Browse and delete Claude Code sessions interactively."
    )
    parser.add_argument(
        "--project", type=str, default=None,
        help="Filter to sessions matching PROJECT name"
    )
    parser.add_argument(
        "--category", type=str, default=None,
        choices=["empty", "tiny", "normal", "large"],
        help="Pre-filter by category"
    )
    parser.add_argument(
        "--older-than", type=int, default=None, metavar="DAYS",
        help="Pre-filter sessions older than N days"
    )
    parser.add_argument(
        "--sort", type=str, default="date",
        choices=["date", "size", "msgs"],
        help="Sort order (default: date desc)"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be deleted without deleting"
    )
    parser.add_argument(
        "--no-fzf", action="store_true",
        help="Non-interactive: print table to stdout"
    )
    parser.add_argument(
        "--preview", type=str, default=None, metavar="SESSION_ID",
        help="Internal: preview callback for fzf"
    )
    parser.add_argument(
        "--auto-empty", action="store_true",
        help="Auto-select all empty/queue-marker sessions"
    )
    parser.add_argument(
        "--stats", action="store_true",
        help="Print summary stats only"
    )
    args = parser.parse_args()

    # Scan all sessions
    sessions = scan_projects()

    # Preview callback (used internally by fzf)
    if args.preview:
        handle_preview(args.preview, sessions)
        return

    # Apply filters
    filtered = apply_filters(sessions, args)

    # Stats only
    if args.stats:
        print_stats(filtered)
        return

    if not filtered:
        print("No sessions match the given filters.")
        return

    # Non-interactive table
    if args.no_fzf:
        print(f"\n{'ID':<10}  {'Project':<14}  {'Date':<12}  {'Size':>6}  "
              f"{'Msgs':>6}  {'Cat':<6}  Description")
        print("─" * 100)
        for si in filtered:
            print(format_table_line(si))
        print(f"\n{len(filtered)} sessions, "
              f"{human_size(sum(s.total_size_bytes for s in filtered))} total")
        return

    # Auto-empty mode
    if args.auto_empty:
        selected = [si for si in filtered if si.category == "empty"]
        if not selected:
            print("No empty sessions found.")
            return
    else:
        # Interactive fzf selection
        selected = run_fzf(filtered)

    if not selected:
        print("No sessions selected.")
        return

    # Confirm and delete
    if confirm_deletion(selected, dry_run=args.dry_run):
        stats = delete_sessions(selected, dry_run=args.dry_run)
        print(f"\nDone: {stats['deleted']} deleted, "
              f"{stats['failed']} failed, "
              f"{human_size(stats['bytes_freed'])} freed.")
    elif args.dry_run:
        pass  # already printed in confirm_deletion
    else:
        print("Cancelled.")


if __name__ == "__main__":
    main()
