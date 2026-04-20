#!/usr/bin/env python
"""Claude Code session management — unified CLI.

Subcommands:
  browse      Interactive fzf browser (default) — ctrl-r renames, enter deletes
  list        All projects with path status (MISSING paths = migration candidates)
  sessions    Per-session info for one project (UUIDs, dates, history status)
  stats       Summary statistics
  delete      Delete sessions by filter
  rename      Set a session's custom title
  search      Search user prompts across all sessions
  migrate     Rewrite session paths after moving/renaming a folder
  export      Pack sessions into a portable .tar.gz
  import      Unpack archive and rewrite paths
  repair      Audit & fix orphaned/ghost sessions, stale cwd paths
  resume      Register a session in history.jsonl for `claude --resume`

Without a subcommand, opens the interactive browser.
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
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


# ── Constants ────────────────────────────────────────────────────────────────

CLAUDE_DIR = Path.home() / ".claude"
PROJECTS_DIR = CLAUDE_DIR / "projects"
SESSION_ENV_DIR = CLAUDE_DIR / "session-env"
HISTORY_JSONL = CLAUDE_DIR / "history.jsonl"
FILE_HISTORY_DIR = CLAUDE_DIR / "file-history"
TODOS_DIR = CLAUDE_DIR / "todos"
TASKS_DIR = CLAUDE_DIR / "tasks"

ACTIVE_THRESHOLD_SECS = 60
LARGE_FILE_THRESHOLD = 50 * 1024
LARGE_SESSION_THRESHOLD = 1 * 1024 * 1024
TINY_MSG_THRESHOLD = 5
TINY_SIZE_THRESHOLD = 5 * 1024
EMPTY_SIZE_THRESHOLD = 500

EXPORT_FORMAT_VERSION = 1
EXPORT_MAGIC = "claude-session-export"

SKIP_USER_MESSAGES = frozenset({
    "/quit", "/exit", "/status", "/help", "/clear",
    "[Request interrupted by user for tool use]",
    "[Request interrupted by user]",
})

SYSTEM_BLOCK_TAGS = (
    "local-command-caveat", "system-reminder", "command-message",
    "command-name", "user-prompt-submit-hook", "environment_details",
    "claude_code_context", "antml:thinking", "fast_mode_info",
)
_block_pattern = "|".join(re.escape(t) for t in SYSTEM_BLOCK_TAGS)
SYSTEM_BLOCK_RE = re.compile(
    rf"<({_block_pattern})\b[^>]*>[\s\S]*?</\1>", re.DOTALL,
)
TAG_RE = re.compile(r"<[^>]+>")
ANSI_RE = re.compile(r"\033\[[0-9;]*m")

C_RESET = "\033[0m"
C_RED = "\033[31m"
C_YELLOW = "\033[33m"
C_CYAN = "\033[36m"
C_GREEN = "\033[32m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"


# ── SessionInfo ──────────────────────────────────────────────────────────────

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
    category: str = "normal"
    git_branch: str = ""
    project_path: str = ""
    is_active: bool = False
    user_messages: list = field(default_factory=list)
    msg_type_counts: dict = field(default_factory=dict)
    custom_title: str = ""


# ── Basic helpers ────────────────────────────────────────────────────────────

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


def human_size(nbytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if abs(nbytes) < 1024:
            if unit == "B":
                return f"{nbytes}{unit}"
            return f"{nbytes:.1f}{unit}"
        nbytes /= 1024
    return f"{nbytes:.1f}TB"


def format_date(ts: float) -> str:
    if ts <= 0:
        return "??/?? ??:??"
    dt = datetime.fromtimestamp(ts)
    return dt.strftime("%m/%d %H:%M")


def truncate(text: str, width: int) -> str:
    text = text.replace("\n", " ").replace("\r", "").replace("\t", " ")
    if len(text) <= width:
        return text
    return text[: width - 3] + "..."


def trunc_middle(text: str, width: int) -> str:
    """Truncate text by keeping both ends with middle ellipsis."""
    text = text.replace("\n", " ").replace("\r", "").replace("\t", " ")
    if len(text) <= width:
        return text
    if width <= 3:
        return text[:width]
    remaining = width - 3
    head_len = (remaining + 1) // 2
    tail_len = remaining // 2
    return text[:head_len] + "..." + text[-tail_len:]


def clean_display_text(text: str) -> str:
    text = SYSTEM_BLOCK_RE.sub("", text)
    text = TAG_RE.sub("", text)
    text = " ".join(text.split())
    return text.strip()


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def category_color(cat: str, active: bool = False) -> str:
    if active:
        return C_GREEN + C_BOLD
    return {
        "empty": C_RED, "tiny": C_YELLOW, "normal": "", "large": C_CYAN,
    }.get(cat, "")


# ── Path helpers ─────────────────────────────────────────────────────────────

def path_to_dirname(path: str) -> str:
    """/Users/foo/bar -> -Users-foo-bar"""
    return os.path.normpath(os.path.abspath(path)).replace("/", "-")


def dirname_to_path(dirname: str) -> str:
    """-Users-foo-bar -> /Users/foo/bar (lossy, prefer cwd from JSONL)."""
    return dirname.replace("-", "/")


def shorten_home(path: str) -> str:
    if not path:
        return path
    home = str(Path.home())
    if path.startswith(home):
        return "~" + path[len(home):]
    return path


def readable_project_name(project_dir_name: str) -> str:
    r = project_dir_name.replace("-", "/")
    if not r:
        return project_dir_name
    return shorten_home(r)


def display_path(si: SessionInfo) -> str:
    """Prefer accurate project_path (from JSONL cwd) over lossy dir-name."""
    if si.project_path:
        return shorten_home(si.project_path)
    return si.project_name


# ── JSONL parsing ────────────────────────────────────────────────────────────

def extract_text_from_content(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text":
                    parts.append(block.get("text", ""))
            elif isinstance(block, str):
                parts.append(block)
        return " ".join(parts)
    return ""


def parse_jsonl_lines(lines: list[str], collect_user_msgs: bool = False) -> dict:
    info = {
        "message_count": 0, "user_messages": [], "last_message": "",
        "first_prompt": "", "created": None, "modified": None,
        "git_branch": "", "project_path": "", "msg_type_counts": {},
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
            text = extract_text_from_content(msg.get("content", "")).strip()
            if text and text not in SKIP_USER_MESSAGES:
                if not info["first_prompt"]:
                    info["first_prompt"] = text
                info["last_message"] = text
                if collect_user_msgs:
                    info["user_messages"].append(text)

    return info


def read_file_smart(path: Path) -> list[str]:
    """Read a JSONL, using seek optimization for large files."""
    try:
        size = path.stat().st_size
    except OSError:
        return []
    if size <= LARGE_FILE_THRESHOLD:
        try:
            return path.read_text(errors="replace").splitlines()
        except OSError:
            return []

    lines = []
    try:
        with open(path, "r", errors="replace") as f:
            for i, line in enumerate(f):
                if i >= 50:
                    break
                lines.append(line)
            f.seek(0, 2)
            file_size = f.tell()
            seek_pos = max(0, file_size - 100 * 1024)
            f.seek(seek_pos)
            if seek_pos > 0:
                f.readline()
            tail = f.readlines()
            tail = tail[-50:]
            lines.extend(tail)
    except OSError:
        pass
    return lines


def read_file_full(path: Path) -> list[str]:
    try:
        return path.read_text(errors="replace").splitlines()
    except OSError:
        return []


def extract_custom_title(path: Path) -> str:
    """Most recent custom-title entry in a JSONL."""
    try:
        content = path.read_text(errors="replace")
    except OSError:
        return ""
    last_title = ""
    for line in content.splitlines():
        if "custom-title" not in line:
            continue
        try:
            entry = json.loads(line)
            if entry.get("type") == "custom-title":
                t = entry.get("customTitle", "")
                if t:
                    last_title = t
        except (json.JSONDecodeError, ValueError):
            continue
    return last_title


def extract_cwd_from_project(project_dir: Path) -> str:
    """Read actual cwd from first session; dirname encoding is lossy."""
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


def extract_first_user_message(jsonl_path: Path, max_chars: int = 80) -> str:
    try:
        with open(jsonl_path, "r", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    entry = json.loads(stripped)
                except (json.JSONDecodeError, ValueError):
                    continue
                if entry.get("type") != "user":
                    continue
                msg = entry.get("message", {})
                content = msg.get("content", "")
                text = ""
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "text":
                            text = c.get("text", "")
                            break
                text = re.sub(r"<command-[^>]*>[^<]*</command-[^>]*>", "", text).strip()
                if text:
                    return text[:max_chars] + ("..." if len(text) > max_chars else "")
    except OSError:
        pass
    return "(empty)"


def extract_session_timestamp(jsonl_path: Path) -> tuple[str, str]:
    """Return (first_ts_iso, last_ts_iso)."""
    first_ts = None
    last_ts = None
    try:
        with open(jsonl_path, "r", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    entry = json.loads(stripped)
                except (json.JSONDecodeError, ValueError):
                    continue
                ts = entry.get("timestamp")
                if ts and isinstance(ts, (int, float)):
                    if first_ts is None:
                        first_ts = ts
                    last_ts = ts
    except OSError:
        pass

    def fmt(ts):
        if ts is None:
            return "?"
        try:
            return datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d %H:%M")
        except (OSError, ValueError):
            return "?"
    return fmt(first_ts), fmt(last_ts)


# ── Session scanning ─────────────────────────────────────────────────────────

def load_sessions_index(project_dir: Path) -> dict:
    index_path = project_dir / "sessions-index.json"
    if not index_path.exists():
        return {}
    try:
        idx = json.loads(index_path.read_text(errors="replace"))
    except (json.JSONDecodeError, OSError):
        return {}
    result = {}
    for entry in idx.get("entries", []):
        sid = entry.get("sessionId", "")
        if sid:
            result[sid] = entry
    return result


def classify_session(si: SessionInfo) -> str:
    has_real = si.message_count > 0 or bool(si.first_prompt) or bool(si.last_message)
    if not has_real and si.total_size_bytes < EMPTY_SIZE_THRESHOLD:
        return "empty"
    if not has_real:
        return "empty"
    if si.message_count <= TINY_MSG_THRESHOLD and si.total_size_bytes < TINY_SIZE_THRESHOLD:
        return "tiny"
    if si.total_size_bytes >= LARGE_SESSION_THRESHOLD:
        return "large"
    return "normal"


def build_session_info(
    jsonl: Path, readable: str,
    index_entry: Optional[dict] = None, now: Optional[float] = None,
) -> Optional[SessionInfo]:
    session_id = jsonl.stem
    si = SessionInfo(session_id=session_id, project_name=readable, jsonl_path=jsonl)

    try:
        stat = jsonl.stat()
        si.total_size_bytes = stat.st_size
        si.modified = stat.st_mtime
        si.created = stat.st_ctime
    except OSError:
        return None

    subdir = jsonl.parent / session_id
    if subdir.is_dir():
        si.has_subdir = True
        si.subdir_path = subdir
        si.total_size_bytes += dir_size(subdir)

    if now is None:
        now = time.time()
    si.is_active = (now - si.modified) < ACTIVE_THRESHOLD_SECS

    if index_entry:
        si.is_indexed = True
        si.summary = index_entry.get("summary", "")
        si.first_prompt = index_entry.get("firstPrompt", "")
        si.message_count = index_entry.get("messageCount", 0)
        si.git_branch = index_entry.get("gitBranch", "")
        si.project_path = index_entry.get("projectPath", "")
        created_str = index_entry.get("created", "")
        modified_str = index_entry.get("modified", "")
        try:
            if created_str:
                si.created = datetime.fromisoformat(created_str.replace("Z", "+00:00")).timestamp()
            if modified_str:
                si.modified = datetime.fromisoformat(modified_str.replace("Z", "+00:00")).timestamp()
        except (ValueError, TypeError):
            pass
        lines = read_file_smart(jsonl)
        parsed = parse_jsonl_lines(lines)
        si.last_message = parsed["last_message"]
        si.msg_type_counts = parsed["msg_type_counts"]
    else:
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

    if si.msg_type_counts.get("custom-title", 0) > 0:
        si.custom_title = extract_custom_title(jsonl)

    si.category = classify_session(si)
    return si


def scan_projects() -> list[SessionInfo]:
    if not PROJECTS_DIR.exists():
        return []
    sessions = []
    now = time.time()
    for project_dir in sorted(PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        readable = readable_project_name(project_dir.name)
        index_data = load_sessions_index(project_dir)
        for jsonl in sorted(project_dir.glob("*.jsonl")):
            si = build_session_info(
                jsonl, readable,
                index_entry=index_data.get(jsonl.stem), now=now,
            )
            if si:
                sessions.append(si)
    return sessions


def find_sessions_by_prefix(prefix: str) -> list[Path]:
    matches = []
    if not PROJECTS_DIR.exists():
        return matches
    for project_dir in PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue
        for jsonl in project_dir.glob("*.jsonl"):
            if jsonl.stem.startswith(prefix):
                matches.append(jsonl)
    return matches


def count_sessions(project_dir: Path) -> int:
    try:
        return len(list(project_dir.glob("*.jsonl")))
    except OSError:
        return 0


# ── Display formatting ──────────────────────────────────────────────────────

def format_fzf_line(si: SessionInfo) -> str:
    """Row: dimmed ID | colored project | date | size. Other info in preview."""
    color = category_color(si.category, si.is_active)
    reset = C_RESET if color else ""
    sid_short = si.session_id[:8]
    project = trunc_middle(display_path(si), 28).ljust(28)
    date = format_date(si.modified)
    size = human_size(si.total_size_bytes).rjust(7)
    return (
        f"{C_DIM}{sid_short}{C_RESET}  "
        f"{color}{project}  {date}  {size}{reset}"
    )


def format_table_line(si: SessionInfo) -> str:
    desc = si.custom_title or si.summary or si.last_message or si.first_prompt or "[queue-marker]"
    desc = clean_display_text(desc)
    desc = truncate(desc, 50)
    sid_short = si.session_id[:8]
    project = truncate(display_path(si), 28)
    date = format_date(si.modified)
    size = human_size(si.total_size_bytes).rjust(6)
    msgs = f"{si.message_count}msg".rjust(6)
    cat = si.category.ljust(6)
    active = " [ACTIVE]" if si.is_active else ""
    return (
        f"{sid_short}  {project:<28s}  {date}  {size}  {msgs}  "
        f"{cat}  {desc}{active}"
    )


def format_preview(si: SessionInfo) -> str:
    cat_color = category_color(si.category, si.is_active) or ""
    cat_reset = C_RESET if cat_color else ""

    lines = []
    lines.append(f"{'═' * 50}")
    if si.custom_title:
        lines.append(f"{C_BOLD}{C_YELLOW}{si.custom_title}{C_RESET}")
    lines.append(f"{C_DIM}Session:{C_RESET} {si.session_id}")
    path_str = shorten_home(si.project_path) if si.project_path else si.project_name
    lines.append(f"{C_DIM}Path:{C_RESET}    {C_CYAN}{path_str}{C_RESET}")
    if si.git_branch:
        lines.append(f"{C_DIM}Branch:{C_RESET}  {si.git_branch}")
    lines.append(f"{'─' * 50}")

    jsonl_size = si.jsonl_path.stat().st_size if si.jsonl_path.exists() else 0
    status_parts = [f"{cat_color}{si.category.upper()}{cat_reset}",
                    f"{si.message_count} msgs", human_size(si.total_size_bytes)]
    if not si.is_indexed:
        status_parts.append(f"{C_DIM}not indexed{C_RESET}")
    if si.is_active:
        status_parts.append(f"{C_BOLD}{C_GREEN}[ACTIVE]{C_RESET}")
    lines.append(" · ".join(status_parts))
    lines.append(f"{C_DIM}Created:{C_RESET}  {format_date(si.created)}")
    lines.append(f"{C_DIM}Modified:{C_RESET} {format_date(si.modified)}")
    if si.has_subdir and si.total_size_bytes != jsonl_size:
        lines.append(f"JSONL: {human_size(jsonl_size)} · Subdir: {human_size(si.total_size_bytes - jsonl_size)}")

    if si.msg_type_counts:
        lines.append(f"{'─' * 50}")
        types_compact = " ".join(f"{k}:{v}" for k, v in sorted(si.msg_type_counts.items()))
        lines.append(f"{C_DIM}Types:{C_RESET} {types_compact}")

    if si.summary:
        lines.append(f"{'─' * 50}")
        lines.append(f"{C_DIM}Summary:{C_RESET} {si.summary}")

    full_lines = read_file_full(si.jsonl_path)
    parsed = parse_jsonl_lines(full_lines, collect_user_msgs=True)
    user_msgs = [clean_display_text(m) for m in parsed["user_messages"]]
    user_msgs = [m for m in user_msgs if m]

    if user_msgs:
        lines.append(f"{'─' * 50}")
        lines.append(f"User messages ({len(user_msgs)} total):")
        for i, msg in enumerate(user_msgs[:20]):
            lines.append(f"  [{i + 1}] {truncate(msg, 120)}")
        if len(user_msgs) > 20:
            lines.append(f"  ... and {len(user_msgs) - 20} more")

    lines.append(f"{'═' * 50}")
    return "\n".join(lines)


# ── Filters & sort ───────────────────────────────────────────────────────────

def apply_filters(sessions: list[SessionInfo], args) -> list[SessionInfo]:
    result = sessions
    if getattr(args, "project", None):
        pat = args.project.lower()
        result = [si for si in result if pat in si.project_name.lower()]
    if getattr(args, "category", None):
        result = [si for si in result if si.category == args.category]
    if getattr(args, "older_than", None) is not None:
        cutoff = time.time() - (args.older_than * 86400)
        result = [si for si in result if si.modified < cutoff]
    sort = getattr(args, "sort", "date")
    if sort == "size":
        result.sort(key=lambda s: s.total_size_bytes, reverse=True)
    elif sort == "msgs":
        result.sort(key=lambda s: s.message_count, reverse=True)
    else:
        result.sort(key=lambda s: s.modified, reverse=True)
    return result


# ── fzf UI ───────────────────────────────────────────────────────────────────

def run_fzf(sessions: list[SessionInfo]) -> list[SessionInfo]:
    if not sessions:
        print("No sessions to display.")
        return []
    sid_map = {si.session_id: si for si in sessions}
    fzf_input = "\n".join(format_fzf_line(si) for si in sessions)

    script_path = os.path.abspath(__file__)
    header = (
        "TAB=select  ENTER=delete  ctrl-r=rename  ctrl-a=all  ctrl-d=deselect  ESC=cancel\n"
        "ID        Project                       Date            Size"
    )

    cmd = [
        "fzf",
        "--multi", "--ansi", "--reverse",
        "--header", header,
        "--preview", f"python {script_path} preview {{1}}",
        "--preview-window", "right:45%:wrap",
        "--bind", "ctrl-a:select-all,ctrl-d:deselect-all",
        "--bind", f"ctrl-r:execute(python {script_path} rename-interactive {{1}})+reload(python {script_path} fzf-lines)",
        "--no-separator", "--border=none",
        "--padding=0,1", "--margin=1",
    ]

    try:
        result = subprocess.run(cmd, input=fzf_input, capture_output=True, text=True)
    except FileNotFoundError:
        print("fzf not found. Falling back to numbered list.")
        return fallback_select(sessions)

    if result.returncode != 0:
        return []

    selected = []
    for line in result.stdout.strip().splitlines():
        raw = strip_ansi(line).strip()
        if not raw:
            continue
        sid_prefix = raw[:8].strip()
        for sid, si in sid_map.items():
            if sid.startswith(sid_prefix):
                selected.append(si)
                break
    return selected


def fallback_select(sessions: list[SessionInfo]) -> list[SessionInfo]:
    print(f"\n{'ID':<4}  {'Session':<10}  {'Project':<14}  {'Date':<12}  {'Size':>6}  "
          f"{'Msgs':>6}  {'Cat':<6}  Description")
    print("─" * 100)
    for i, si in enumerate(sessions, 1):
        desc = si.custom_title or si.summary or si.last_message or si.first_prompt or "[queue-marker]"
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
    return [sessions[idx - 1] for idx in indices if 1 <= idx <= len(sessions)]


def parse_range_input(raw: str) -> list[int]:
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


# ── Rename ───────────────────────────────────────────────────────────────────

def rename_session(prefix: str, new_title: str) -> bool:
    matches = find_sessions_by_prefix(prefix)
    if not matches:
        print(f"{C_RED}ERROR: No session found with prefix '{prefix}'.{C_RESET}")
        return False
    if len(matches) > 1:
        print(f"{C_RED}ERROR: Ambiguous prefix '{prefix}' — matches {len(matches)} sessions:{C_RESET}")
        for m in matches:
            print(f"  {m.stem}  ({m.parent.name})")
        return False

    jsonl = matches[0]
    session_id = jsonl.stem
    entry = {"type": "custom-title", "customTitle": new_title, "sessionId": session_id}
    line = json.dumps(entry, ensure_ascii=False, separators=(",", ":"))

    try:
        with open(jsonl, "rb+") as f:
            f.seek(0, 2)
            size = f.tell()
            if size > 0:
                f.seek(size - 1)
                last_byte = f.read(1)
                if last_byte != b"\n":
                    f.write(b"\n")
        with open(jsonl, "a") as f:
            f.write(line + "\n")
    except OSError as e:
        print(f"{C_RED}ERROR writing {jsonl}: {e}{C_RESET}")
        return False

    print(f"{C_GREEN}Renamed {session_id[:8]} → {new_title!r}{C_RESET}")
    return True


def rename_interactive(prefix: str) -> bool:
    """Interactive rename: shows current title, prompts for new one."""
    matches = find_sessions_by_prefix(prefix)
    if not matches:
        print(f"{C_RED}Session {prefix} not found.{C_RESET}")
        return False
    jsonl = matches[0]
    current = extract_custom_title(jsonl)
    print(f"\nSession: {jsonl.stem}")
    if current:
        print(f"Current title: {C_BOLD}{current}{C_RESET}")
    else:
        print(f"{C_DIM}(no custom title set){C_RESET}")
    try:
        new_title = input("New title (blank to cancel): ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return False
    if not new_title:
        print("Cancelled.")
        return False
    return rename_session(jsonl.stem, new_title)


# ── Search ───────────────────────────────────────────────────────────────────

def search_user_prompts(query: str, use_regex: bool = False) -> list[dict]:
    if use_regex:
        try:
            pat = re.compile(query, re.IGNORECASE)
        except re.error as e:
            print(f"{C_RED}ERROR: Invalid regex: {e}{C_RESET}")
            return []
    else:
        pat = None
        q_lower = query.lower()

    results = []
    if not PROJECTS_DIR.exists():
        return results

    for project_dir in sorted(PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        project_name = project_dir.name.replace("-", "/")
        for jsonl in sorted(project_dir.glob("*.jsonl")):
            try:
                lines = jsonl.read_text(errors="replace").splitlines()
            except OSError:
                continue

            custom_title = ""
            project_path = ""
            match_excerpt = ""
            match_msg_idx = -1
            total_matches = 0
            user_msg_count = 0

            for line in lines:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue

                etype = entry.get("type", "")
                if etype == "custom-title":
                    t = entry.get("customTitle", "")
                    if t:
                        custom_title = t
                    continue
                if etype == "user":
                    msg = entry.get("message", {})
                    if not isinstance(msg, dict) or msg.get("role") != "user":
                        continue
                    text = extract_text_from_content(msg.get("content", ""))
                    text = clean_display_text(text)
                    if not text or text in SKIP_USER_MESSAGES:
                        continue
                    user_msg_count += 1
                    matched = (pat.search(text) if pat else q_lower in text.lower())
                    if matched:
                        total_matches += 1
                        if not match_excerpt:
                            match_excerpt = text
                            match_msg_idx = user_msg_count
                    if not project_path and entry.get("cwd"):
                        project_path = entry.get("cwd", "")

            if total_matches > 0:
                results.append({
                    "session_id": jsonl.stem,
                    "project_name": project_name,
                    "project_path": project_path,
                    "jsonl_path": jsonl,
                    "custom_title": custom_title,
                    "match_excerpt": match_excerpt,
                    "match_msg_idx": match_msg_idx,
                    "total_matches": total_matches,
                })
    return results


def run_search_fzf(results: list[dict]) -> Optional[dict]:
    if not results:
        return None
    results.sort(key=lambda r: (-r["total_matches"], r["project_name"]))

    fzf_lines = []
    for r in results:
        sid_short = r["session_id"][:8]
        project = truncate(shorten_home(r["project_path"] or r["project_name"]).lstrip("/"), 22)
        title = r["custom_title"] or r["match_excerpt"]
        title = truncate(clean_display_text(title), 60)
        n = r["total_matches"]
        fzf_lines.append(f"{sid_short}  {project:<22s}  {n:>2} hit  {title}")

    fzf_input = "\n".join(fzf_lines)
    header = (
        f"{len(results)} sessions matched · ENTER=show resume command · ESC=cancel\n"
        "ID        Project                 Hits  Title/Excerpt"
    )
    cmd = ["fzf", "--ansi", "--reverse", "--header", header, "--no-multi",
           "--no-separator", "--border=none", "--padding=0,1", "--margin=1"]
    try:
        proc = subprocess.run(cmd, input=fzf_input, capture_output=True, text=True)
    except FileNotFoundError:
        for i, line in enumerate(fzf_lines, 1):
            print(f"  [{i}] {line}")
        try:
            raw = input("\nPick number (or q): ").strip()
        except (EOFError, KeyboardInterrupt):
            return None
        try:
            idx = int(raw)
            if 1 <= idx <= len(results):
                return results[idx - 1]
        except ValueError:
            return None
        return None

    if proc.returncode != 0:
        return None
    selected = proc.stdout.strip()
    if not selected:
        return None
    sid_prefix = selected[:8].strip()
    for r in results:
        if r["session_id"].startswith(sid_prefix):
            return r
    return None


# ── Delete ───────────────────────────────────────────────────────────────────

def confirm_deletion(sessions: list[SessionInfo], dry_run: bool = False) -> bool:
    total_bytes = sum(si.total_size_bytes for si in sessions)
    prefix = "[DRY RUN] " if dry_run else ""
    print(f"\n{prefix}About to delete {len(sessions)} session(s) "
          f"(total {human_size(total_bytes)}):\n")
    for si in sessions:
        active = " [ACTIVE!]" if si.is_active else ""
        desc = si.custom_title or si.summary or si.last_message or si.first_prompt or "[queue-marker]"
        desc = clean_display_text(desc)
        desc = truncate(desc, 45)
        print(
            f"  {si.session_id[:8]}  {truncate(si.project_name, 14):<14}  "
            f"{human_size(si.total_size_bytes):>6}  {si.category:<6}  {desc}{active}"
        )
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


def trash_path(path: Path) -> bool:
    try:
        subprocess.run(["/usr/bin/trash", str(path)], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
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


def delete_sessions(sessions: list[SessionInfo], dry_run: bool = False) -> dict:
    stats = {"deleted": 0, "failed": 0, "bytes_freed": 0, "details": []}
    for si in sessions:
        if si.is_active:
            print(f"  SKIP {si.session_id[:8]}: active session")
            stats["details"].append((si.session_id[:8], "skipped (active)"))
            continue
        success = True
        if si.jsonl_path.exists() and not dry_run:
            if not trash_path(si.jsonl_path):
                success = False
        if si.has_subdir and si.subdir_path and si.subdir_path.exists() and not dry_run:
            if not trash_path(si.subdir_path):
                success = False
        env_dir = SESSION_ENV_DIR / si.session_id
        if env_dir.exists() and not dry_run:
            if not trash_path(env_dir):
                success = False
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


# ── Listing / stats ──────────────────────────────────────────────────────────

def print_stats(sessions: list[SessionInfo]) -> None:
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
    env_count = 0
    if SESSION_ENV_DIR.exists():
        try:
            env_count = len(list(SESSION_ENV_DIR.iterdir()))
        except OSError:
            pass
    if env_count:
        print(f"  Session-env: {env_count} dirs")


def list_projects():
    if not PROJECTS_DIR.exists():
        print("No projects directory found.")
        return
    projects = []
    for project_dir in sorted(PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue
        dirname = project_dir.name
        actual_path = extract_cwd_from_project(project_dir)
        if not actual_path:
            actual_path = dirname_to_path(dirname)
        n_sessions = count_sessions(project_dir)
        size = dir_size(project_dir)
        exists = os.path.isdir(actual_path)
        projects.append((actual_path, n_sessions, size, exists, dirname))
    if not projects:
        print("No project sessions found.")
        return

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
        print(f"\nTo migrate: python {sys.argv[0]} migrate /old/path /new/path")


def list_sessions(project_path: str):
    project_path = os.path.normpath(os.path.abspath(project_path))
    encoded = path_to_dirname(project_path)
    project_dir = PROJECTS_DIR / encoded

    if not project_dir.exists():
        for candidate in PROJECTS_DIR.iterdir():
            if candidate.is_dir() and extract_cwd_from_project(candidate) == project_path:
                project_dir = candidate
                encoded = candidate.name
                break
        else:
            print(f"{C_RED}ERROR: No sessions found for: {project_path}{C_RESET}")
            print(f"  Looked for: {project_dir}")
            return

    print(f"\n{C_BOLD}Sessions for:{C_RESET} {project_path}")
    print(f"  Project dir: {project_dir}\n")
    jsonl_files = sorted(project_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
    if not jsonl_files:
        print(f"  {C_YELLOW}No session files found.{C_RESET}")
        return

    history_sids = set()
    if HISTORY_JSONL.exists():
        try:
            for line in HISTORY_JSONL.read_text(errors="replace").splitlines():
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    entry = json.loads(stripped)
                    if entry.get("project") == project_path:
                        sid = entry.get("sessionId", "")
                        if sid:
                            history_sids.add(sid)
                except (json.JSONDecodeError, ValueError):
                    continue
        except OSError:
            pass

    active_sids = set()
    sessions_dir = CLAUDE_DIR / "sessions"
    if sessions_dir.exists():
        for sf in sessions_dir.glob("*.json"):
            try:
                data = json.loads(sf.read_text(errors="replace"))
                sid = data.get("sessionId", "")
                if sid:
                    active_sids.add(sid)
            except (json.JSONDecodeError, OSError):
                continue

    print(f"{'#':<3}  {'Session ID':<38}  {'Last Modified':<18}  {'Size':>8}  {'Status':<12}  First Message")
    print("─" * 140)
    for i, jsonl in enumerate(jsonl_files, 1):
        sid = jsonl.stem
        size = jsonl.stat().st_size
        mtime = datetime.fromtimestamp(jsonl.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        first_msg = extract_first_user_message(jsonl)
        statuses = []
        if sid in active_sids:
            statuses.append(f"{C_GREEN}ACTIVE{C_RESET}")
        if sid in history_sids:
            statuses.append(f"{C_GREEN}in-hist{C_RESET}")
        else:
            statuses.append(f"{C_RED}no-hist{C_RESET}")
        if (project_dir / sid).is_dir():
            statuses.append("dir")
        status_str = ",".join(statuses)
        print(f"{i:<3}  {sid:<38}  {mtime:<18}  {human_size(size):>8}  {status_str:<12}  {first_msg}")

    memory_dir = project_dir / "memory"
    if memory_dir.is_dir():
        mem_files = list(memory_dir.glob("*.md"))
        print(f"\n  Memory: {len(mem_files)} file(s)")
    print(f"\n  Total: {len(jsonl_files)} session(s)")
    print(f"  {C_DIM}Status key: ACTIVE=running process, in-hist=in history.jsonl, no-hist=orphaned, dir=has companion dir{C_RESET}")


# ── Migrate ──────────────────────────────────────────────────────────────────

def update_jsonl_cwd(jsonl_path: Path, old_path: str, new_path: str, dry_run: bool) -> int:
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
        if "cwd" in entry and isinstance(entry["cwd"], str):
            if entry["cwd"] == old_path or entry["cwd"].startswith(old_path + "/"):
                entry["cwd"] = entry["cwd"].replace(old_path, new_path, 1)
                changed = True
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
    if not HISTORY_JSONL.exists():
        return 0
    try:
        lines = HISTORY_JSONL.read_text(errors="replace").splitlines()
    except OSError:
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
        if "project" in entry and isinstance(entry["project"], str):
            if entry["project"] == old_path or entry["project"].startswith(old_path + "/"):
                entry["project"] = entry["project"].replace(old_path, new_path, 1)
                changed = True
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
        backup_path = HISTORY_JSONL.with_suffix(".jsonl.bak")
        try:
            shutil.copy2(HISTORY_JSONL, backup_path)
        except OSError:
            pass
        try:
            HISTORY_JSONL.write_text("\n".join(new_lines) + "\n" if new_lines else "")
        except OSError:
            return 0
    return updated_count


def update_sessions_index(index_path: Path, old_path: str, new_path: str, dry_run: bool) -> int:
    if not index_path.exists():
        return 0
    try:
        data = json.loads(index_path.read_text(errors="replace"))
    except (json.JSONDecodeError, OSError):
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
        except OSError:
            return 0
    return updated


def migrate(old_path: str, new_path: str, dry_run: bool = False) -> bool:
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
    print()

    if not old_project_dir.exists():
        print(f"{C_RED}ERROR: No sessions found for old path.{C_RESET}")
        print(f"  Expected: {old_project_dir}")
        return False

    n_sessions = count_sessions(old_project_dir)
    total_size = dir_size(old_project_dir)
    print(f"  Found {n_sessions} session(s), {human_size(total_size)} total")

    if new_project_dir.exists():
        n_existing = count_sessions(new_project_dir)
        if n_existing > 0:
            print(f"\n{C_YELLOW}WARNING: Target already has {n_existing} session(s). "
                  f"Files will be merged (no overwrites).{C_RESET}")

    if not dry_run:
        try:
            answer = input(f"\nProceed with migration? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\nCancelled.")
            return False
        if answer not in ("y", "yes"):
            print("Cancelled.")
            return False

    if not dry_run:
        new_project_dir.mkdir(parents=True, exist_ok=True)

    files_moved = 0
    for item in sorted(old_project_dir.iterdir()):
        target = new_project_dir / item.name
        if target.exists():
            print(f"  {C_DIM}SKIP (exists): {item.name}{C_RESET}")
            continue
        if not dry_run:
            shutil.move(str(item), str(target))
        print(f"  {prefix}MOVE: {item.name}")
        files_moved += 1

    jsonl_updated = 0
    print(f"\n{prefix}Updating paths in session files...")
    for jsonl in sorted(new_project_dir.glob("*.jsonl")):
        n = update_jsonl_cwd(jsonl, old_path, new_path, dry_run)
        if n > 0:
            print(f"  {prefix}{jsonl.name}: {n} entries updated")
            jsonl_updated += n

    index_path = new_project_dir / "sessions-index.json"
    n_idx = update_sessions_index(index_path, old_path, new_path, dry_run)
    if n_idx > 0:
        print(f"  {prefix}sessions-index.json: {n_idx} entries updated")

    print(f"\n{prefix}Updating history.jsonl...")
    n_hist = update_history_jsonl(old_path, new_path, dry_run)
    if n_hist > 0:
        print(f"  {prefix}history.jsonl: {n_hist} entries updated")

    if not dry_run:
        try:
            remaining = list(old_project_dir.iterdir())
            if not remaining:
                old_project_dir.rmdir()
                print(f"\n  Removed empty old directory: {old_dirname}")
        except OSError:
            pass

    print(f"\n{C_GREEN}{'[DRY RUN] ' if dry_run else ''}Migration complete!{C_RESET}")
    print(f"  Files moved:    {files_moved}")
    print(f"  Paths updated:  {jsonl_updated}")
    print(f"  History entries: {n_hist}")
    print(f"\nYou can now resume sessions with: cd {new_path} && claude --resume")
    return True


# ── Migrate interactive (--here equivalent) ──────────────────────────────────

def collect_missing_projects() -> list:
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
            size = dir_size(project_dir)
            missing.append((actual_path, n_sessions, size, dirname))
    return missing


def collect_all_projects() -> list:
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
        size = dir_size(project_dir)
        exists = os.path.isdir(actual_path)
        projects.append((actual_path, n_sessions, size, dirname, exists))
    return projects


def select_source_fzf(
    target_path: Optional[str] = None, show_all: bool = False,
    header_prefix: str = "Select source project to migrate INTO",
) -> Optional[str]:
    if show_all:
        projects = collect_all_projects()
        if target_path:
            projects = [(p, n, s, d, e) for p, n, s, d, e in projects
                        if os.path.normpath(p) != os.path.normpath(target_path)]
    else:
        projects = collect_missing_projects()

    if not projects:
        if show_all:
            print(f"{C_YELLOW}No other projects with sessions found.{C_RESET}")
        else:
            print(f"{C_YELLOW}No projects with missing paths found. Use --all to see all.{C_RESET}")
        return None

    fzf_lines = []
    for item in projects:
        if show_all:
            path, n, size, dirname, exists = item
            status = f"{C_GREEN}EXISTS{C_RESET}" if exists else f"{C_RED}MISSING{C_RESET}"
        else:
            path, n, size, dirname = item
            status = f"{C_RED}MISSING{C_RESET}"
        fzf_lines.append(f"{shorten_home(path):<60}  {n:>3} sessions  {human_size(size):>8}  {status}")

    fzf_input = "\n".join(fzf_lines)
    header_target = f": {target_path}" if target_path else ""
    header = (
        f"{header_prefix}{header_target}\n"
        f"{'Path':<60}  {'Sessions':>12}  {'Size':>8}  Status"
    )
    cmd = ["fzf", "--ansi", "--reverse", "--header", header, "--no-multi",
           "--no-separator", "--border=none", "--padding=0,1", "--margin=1"]

    try:
        result = subprocess.run(cmd, input=fzf_input, capture_output=True, text=True)
    except FileNotFoundError:
        return None
    if result.returncode != 0:
        return None
    selected = result.stdout.strip()
    if not selected:
        return None
    raw = strip_ansi(selected).strip()
    match = re.match(r"^(.+?)\s{2,}\d+\s+sessions", raw)
    if match:
        path = match.group(1).strip()
        # Un-shorten ~ back to $HOME
        if path.startswith("~"):
            path = str(Path.home()) + path[1:]
        return path
    return None


# ── Export / Import ─────────────────────────────────────────────────────────

def collect_session_ids(project_dir: Path) -> list[str]:
    ids = []
    try:
        for jsonl in project_dir.glob("*.jsonl"):
            stem = jsonl.stem
            if re.match(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", stem):
                ids.append(stem)
    except OSError:
        pass
    return sorted(ids)


def collect_satellite_paths(session_ids: list[str]) -> dict[str, list[Path]]:
    result: dict[str, list[Path]] = {"file_history": [], "todos": [], "tasks": []}
    for sid in session_ids:
        fh_dir = FILE_HISTORY_DIR / sid
        if fh_dir.is_dir():
            result["file_history"].append(fh_dir)
        if TODOS_DIR.exists():
            for todo_file in TODOS_DIR.glob(f"{sid}*.json"):
                result["todos"].append(todo_file)
        task_dir = TASKS_DIR / sid
        if task_dir.is_dir():
            result["tasks"].append(task_dir)
    return result


def extract_history_entries(original_path: str) -> list[str]:
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


def export_project(project_path: str, output_file: Optional[str], dry_run: bool = False) -> bool:
    project_path = os.path.normpath(os.path.abspath(project_path))
    encoded = path_to_dirname(project_path)
    project_dir = PROJECTS_DIR / encoded

    print(f"\n{C_BOLD}Claude Session Export{C_RESET}")
    print("─" * 50)
    print(f"  Project: {project_path}")

    if not project_dir.exists():
        for candidate in PROJECTS_DIR.iterdir():
            if candidate.is_dir() and extract_cwd_from_project(candidate) == project_path:
                project_dir = candidate
                encoded = candidate.name
                break
        else:
            print(f"\n{C_RED}ERROR: No sessions found for this project.{C_RESET}")
            return False

    session_ids = collect_session_ids(project_dir)
    n_sessions = count_sessions(project_dir)
    satellites = collect_satellite_paths(session_ids)
    history_entries = extract_history_entries(project_path)
    project_size = dir_size(project_dir)

    fh_size = sum(dir_size(p) for p in satellites["file_history"])
    todo_size = sum(p.stat().st_size for p in satellites["todos"] if p.exists())
    task_size = sum(dir_size(p) for p in satellites["tasks"])
    total_size = project_size + fh_size + todo_size + task_size

    print(f"  Sessions: {n_sessions} ({human_size(project_size)})")
    if satellites["file_history"]:
        print(f"  File history: {len(satellites['file_history'])} session(s) ({human_size(fh_size)})")
    if satellites["todos"]:
        print(f"  Todos: {len(satellites['todos'])} file(s) ({human_size(todo_size)})")
    if satellites["tasks"]:
        print(f"  Tasks: {len(satellites['tasks'])} session(s) ({human_size(task_size)})")
    print(f"  History entries: {len(history_entries)}")

    memory_dir = project_dir / "memory"
    has_memory = memory_dir.is_dir() and any(memory_dir.iterdir())
    if has_memory:
        print(f"  Memory: {C_GREEN}yes{C_RESET}")
    print(f"  Total: ~{human_size(total_size)}")

    if dry_run:
        print(f"\n{C_YELLOW}[DRY RUN] No archive created.{C_RESET}")
        return True

    if not output_file:
        basename = os.path.basename(project_path) or "project"
        output_file = f"{basename}-claude-sessions.tar.gz"
    output_path = os.path.abspath(output_file)

    with tempfile.TemporaryDirectory() as tmpdir:
        export_root = Path(tmpdir) / "claude-session-export"
        export_root.mkdir()
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

        shutil.copytree(project_dir, export_root / "projects")
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
        if history_entries:
            (export_root / "history-entries.jsonl").write_text(
                "\n".join(history_entries) + "\n"
            )
        with tarfile.open(output_path, "w:gz") as tar:
            tar.add(str(export_root), arcname="claude-session-export")

    archive_size = os.path.getsize(output_path)
    print(f"\n{C_GREEN}Export complete!{C_RESET}")
    print(f"  Archive: {output_path}")
    print(f"  Size: {human_size(archive_size)} (compressed)")
    print(f"\nTo import: python {sys.argv[0]} import {os.path.basename(output_path)}")
    return True


def import_project(archive_path: str, target_path: str, dry_run: bool = False, conflict: str = "skip") -> bool:
    archive_path = os.path.abspath(archive_path)
    target_path = os.path.normpath(os.path.abspath(target_path))
    prefix = f"{C_YELLOW}[DRY RUN]{C_RESET} " if dry_run else ""

    if not os.path.isfile(archive_path):
        print(f"{C_RED}ERROR: Archive not found: {archive_path}{C_RESET}")
        return False

    print(f"\n{C_BOLD}Claude Session Import{C_RESET}")
    print("─" * 50)

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

        if new_project_dir.exists():
            n_existing = count_sessions(new_project_dir)
            if n_existing > 0:
                if conflict == "abort":
                    print(f"{C_RED}ERROR: Target already has {n_existing} session(s).{C_RESET}")
                    return False
                elif conflict == "skip":
                    print(f"{C_YELLOW}Target has {n_existing} existing — will skip existing files.{C_RESET}")
                else:
                    print(f"{C_YELLOW}Target has {n_existing} existing — will overwrite.{C_RESET}")

        if dry_run:
            print(f"\n{C_YELLOW}[DRY RUN] No changes made.{C_RESET}")
            return True

        try:
            answer = input(f"Proceed with import? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\nCancelled.")
            return False
        if answer not in ("y", "yes"):
            print("Cancelled.")
            return False

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
                        continue
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(item, dest)
                    files_copied += 1

        jsonl_updated = 0
        print(f"\n{prefix}Rewriting paths in session files...")
        for jsonl in sorted(new_project_dir.glob("*.jsonl")):
            n = update_jsonl_cwd(jsonl, original_path, target_path, dry_run=False)
            if n > 0:
                print(f"  {jsonl.name}: {n} entries updated")
                jsonl_updated += n

        index_path = new_project_dir / "sessions-index.json"
        n_idx = update_sessions_index(index_path, original_path, target_path, dry_run=False)
        if n_idx > 0:
            print(f"  sessions-index.json: {n_idx} entries updated")
        if index_path.exists():
            try:
                data = json.loads(index_path.read_text(errors="replace"))
                changed = False
                for entry in data.get("entries", []):
                    fp = entry.get("fullPath", "")
                    if fp:
                        basename = os.path.basename(fp)
                        entry["fullPath"] = str(new_project_dir / basename)
                        changed = True
                if "originalPath" in data:
                    data["originalPath"] = target_path
                    changed = True
                if changed:
                    index_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
            except (json.JSONDecodeError, OSError):
                pass

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
                if HISTORY_JSONL.exists():
                    backup = HISTORY_JSONL.with_suffix(".jsonl.bak")
                    try:
                        shutil.copy2(HISTORY_JSONL, backup)
                    except OSError:
                        pass
                with open(HISTORY_JSONL, "a") as f:
                    f.write("\n".join(new_entries) + "\n")
                print(f"  History: {len(new_entries)} entries merged")

    print(f"\n{C_GREEN}Import complete!{C_RESET}")
    print(f"  Files copied:   {files_copied}")
    print(f"  Paths rewritten: {jsonl_updated}")
    print(f"\nYou can now resume: cd {target_path} && claude --resume")
    return True


# ── Repair / Resume ─────────────────────────────────────────────────────────

def repair_project(project_path: str, dry_run: bool = False) -> bool:
    project_path = os.path.normpath(os.path.abspath(project_path))
    encoded = path_to_dirname(project_path)
    project_dir = PROJECTS_DIR / encoded
    prefix = f"{C_YELLOW}[DRY RUN]{C_RESET} " if dry_run else ""

    if not project_dir.exists():
        for candidate in PROJECTS_DIR.iterdir():
            if candidate.is_dir() and extract_cwd_from_project(candidate) == project_path:
                project_dir = candidate
                encoded = candidate.name
                break
        else:
            print(f"{C_RED}ERROR: No sessions found for: {project_path}{C_RESET}")
            return False

    print(f"\n{C_BOLD}Session Repair: {project_path}{C_RESET}")
    print("─" * 60)
    session_ids = collect_session_ids(project_dir)
    print(f"  Session files: {len(session_ids)}")

    history_entries = {}
    if HISTORY_JSONL.exists():
        try:
            for line in HISTORY_JSONL.read_text(errors="replace").splitlines():
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    entry = json.loads(stripped)
                    if entry.get("project") == project_path:
                        sid = entry.get("sessionId", "")
                        if sid:
                            history_entries.setdefault(sid, []).append(entry)
                except (json.JSONDecodeError, ValueError):
                    continue
        except OSError:
            pass

    history_sids = set(history_entries.keys())
    file_sids = set(session_ids)
    orphaned = file_sids - history_sids
    ghost = history_sids - file_sids

    issues = 0
    if orphaned:
        print(f"\n  {C_YELLOW}Orphaned sessions (file exists, not in history.jsonl):{C_RESET}")
        for sid in sorted(orphaned):
            jsonl = project_dir / f"{sid}.jsonl"
            size = jsonl.stat().st_size if jsonl.exists() else 0
            first_msg = extract_first_user_message(jsonl)
            print(f"    {sid}  {human_size(size):>8}  {first_msg}")
        issues += len(orphaned)

    if ghost:
        print(f"\n  {C_YELLOW}Ghost history entries (in history, no file): {len(ghost)}{C_RESET}")
        issues += len(ghost)

    path_mismatches = 0
    for sid in session_ids:
        jsonl = project_dir / f"{sid}.jsonl"
        try:
            with open(jsonl, "r", errors="replace") as f:
                for line in f:
                    stripped = line.strip()
                    if not stripped:
                        continue
                    try:
                        entry = json.loads(stripped)
                        cwd = entry.get("cwd", "")
                        if cwd and cwd != project_path and not cwd.startswith(project_path + "/"):
                            path_mismatches += 1
                            break
                    except (json.JSONDecodeError, ValueError):
                        continue
        except OSError:
            continue

    if path_mismatches:
        print(f"\n  {C_YELLOW}Sessions with stale cwd paths: {path_mismatches}{C_RESET}")
        issues += path_mismatches

    if issues == 0:
        print(f"\n  {C_GREEN}No issues found!{C_RESET}")
        return True

    print(f"\n  Total issues: {issues}")

    if orphaned:
        print(f"\n{prefix}Fixing orphaned sessions...")
        if not dry_run:
            try:
                shutil.copy2(HISTORY_JSONL, HISTORY_JSONL.with_suffix(".jsonl.bak"))
            except OSError:
                pass
        new_entries = []
        for sid in sorted(orphaned):
            jsonl = project_dir / f"{sid}.jsonl"
            first_msg = extract_first_user_message(jsonl, max_chars=120)
            last_ts_ms = None
            try:
                with open(jsonl, "r", errors="replace") as f:
                    for line in f:
                        stripped = line.strip()
                        if not stripped:
                            continue
                        try:
                            entry = json.loads(stripped)
                            ts = entry.get("timestamp")
                            if ts and isinstance(ts, (int, float)):
                                last_ts_ms = int(ts)
                        except (json.JSONDecodeError, ValueError):
                            continue
            except OSError:
                pass
            if last_ts_ms is None:
                last_ts_ms = int(jsonl.stat().st_mtime * 1000)
            history_entry = {
                "display": first_msg, "pastedContents": {},
                "timestamp": last_ts_ms, "project": project_path, "sessionId": sid,
            }
            new_entries.append(json.dumps(history_entry, ensure_ascii=False))
            print(f"  {prefix}ADD: {sid}  ({first_msg[:60]})")
        if new_entries and not dry_run:
            try:
                with open(HISTORY_JSONL, "a") as f:
                    f.write("\n".join(new_entries) + "\n")
                print(f"  {C_GREEN}Added {len(new_entries)} entries{C_RESET}")
            except OSError as e:
                print(f"  {C_RED}ERROR: {e}{C_RESET}")

    if path_mismatches:
        print(f"\n{prefix}Fixing stale cwd paths...")
        for sid in session_ids:
            jsonl = project_dir / f"{sid}.jsonl"
            old_cwd = None
            try:
                with open(jsonl, "r", errors="replace") as f:
                    for line in f:
                        stripped = line.strip()
                        if not stripped:
                            continue
                        try:
                            entry = json.loads(stripped)
                            cwd = entry.get("cwd", "")
                            if cwd and cwd != project_path and not cwd.startswith(project_path + "/"):
                                old_cwd = cwd
                                break
                        except (json.JSONDecodeError, ValueError):
                            continue
            except OSError:
                continue
            if old_cwd:
                n = update_jsonl_cwd(jsonl, old_cwd, project_path, dry_run)
                if n > 0:
                    print(f"  {prefix}{sid}: {n} entries fixed")

    print(f"\n{C_GREEN}{'[DRY RUN] ' if dry_run else ''}Repair complete!{C_RESET}")
    return True


def resume_session_by_id(session_id: str) -> bool:
    print(f"\n{C_BOLD}Resume Session Setup{C_RESET}")
    print(f"  Session ID: {session_id}")

    found_project_dir = None
    found_project_path = None
    for project_dir in PROJECTS_DIR.iterdir():
        if not project_dir.is_dir():
            continue
        jsonl = project_dir / f"{session_id}.jsonl"
        if jsonl.exists():
            found_project_dir = project_dir
            found_project_path = extract_cwd_from_project(project_dir)
            if not found_project_path:
                found_project_path = dirname_to_path(project_dir.name)
            break

    if not found_project_dir:
        print(f"\n{C_RED}ERROR: Session {session_id} not found.{C_RESET}")
        return False

    jsonl = found_project_dir / f"{session_id}.jsonl"
    size = jsonl.stat().st_size
    first_msg = extract_first_user_message(jsonl)
    print(f"  Project: {found_project_path}")
    print(f"  Size: {human_size(size)}")
    print(f"  First message: {first_msg}")

    already_in_history = False
    if HISTORY_JSONL.exists():
        try:
            for line in HISTORY_JSONL.read_text(errors="replace").splitlines():
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    entry = json.loads(stripped)
                    if entry.get("sessionId") == session_id:
                        already_in_history = True
                        break
                except (json.JSONDecodeError, ValueError):
                    continue
        except OSError:
            pass

    if already_in_history:
        print(f"\n  {C_GREEN}Already in history.jsonl. To resume:{C_RESET}")
        print(f"    cd {found_project_path} && claude --resume")
        return True

    last_ts_ms = None
    try:
        with open(jsonl, "r", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if not stripped:
                    continue
                try:
                    entry = json.loads(stripped)
                    ts = entry.get("timestamp")
                    if ts and isinstance(ts, (int, float)):
                        last_ts_ms = int(ts)
                except (json.JSONDecodeError, ValueError):
                    continue
    except OSError:
        pass
    if last_ts_ms is None:
        last_ts_ms = int(jsonl.stat().st_mtime * 1000)

    history_entry = {
        "display": first_msg, "pastedContents": {},
        "timestamp": last_ts_ms, "project": found_project_path, "sessionId": session_id,
    }
    try:
        shutil.copy2(HISTORY_JSONL, HISTORY_JSONL.with_suffix(".jsonl.bak"))
    except OSError:
        pass
    try:
        with open(HISTORY_JSONL, "a") as f:
            f.write(json.dumps(history_entry, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"\n{C_RED}ERROR: {e}{C_RESET}")
        return False

    print(f"\n  {C_GREEN}Added to history.jsonl!{C_RESET}")
    print(f"    cd {found_project_path} && claude --resume")
    return True


# ── Preview callback ────────────────────────────────────────────────────────

def handle_preview(session_id_prefix: str) -> None:
    """fzf preview callback — direct lookup, no full scan."""
    matches = find_sessions_by_prefix(session_id_prefix)
    if not matches:
        print(f"Session {session_id_prefix} not found.")
        return
    jsonl = matches[0]
    project_dir = jsonl.parent
    readable = readable_project_name(project_dir.name)
    index_data = load_sessions_index(project_dir)
    si = build_session_info(
        jsonl, readable, index_entry=index_data.get(jsonl.stem),
    )
    if si:
        print(format_preview(si))
    else:
        print(f"Session {session_id_prefix} not found.")


def emit_fzf_lines() -> None:
    """Emit fzf-line format for the reload binding."""
    sessions = scan_projects()
    sessions.sort(key=lambda s: s.modified, reverse=True)
    for si in sessions:
        print(format_fzf_line(si))


# ── CLI ──────────────────────────────────────────────────────────────────────

def _add_filter_args(p):
    p.add_argument("--project", type=str, default=None,
                   help="Filter by project name substring")
    p.add_argument("--category", choices=["empty", "tiny", "normal", "large"],
                   default=None, help="Filter by category")
    p.add_argument("--older-than", type=int, default=None, metavar="DAYS",
                   help="Filter sessions older than N days")
    p.add_argument("--sort", choices=["date", "size", "msgs"], default="date",
                   help="Sort order (default: date)")


def cmd_browse(args):
    sessions = scan_projects()
    filtered = apply_filters(sessions, args)
    if not filtered:
        print("No sessions match the given filters.")
        return 0
    if args.auto_empty:
        selected = [si for si in filtered if si.category == "empty"]
        if not selected:
            print("No empty sessions found.")
            return 0
    else:
        selected = run_fzf(filtered)
    if not selected:
        print("No sessions selected.")
        return 0
    if confirm_deletion(selected, dry_run=args.dry_run):
        stats = delete_sessions(selected, dry_run=args.dry_run)
        print(f"\nDone: {stats['deleted']} deleted, {stats['failed']} failed, "
              f"{human_size(stats['bytes_freed'])} freed.")
    elif args.dry_run:
        pass
    else:
        print("Cancelled.")
    return 0


def cmd_delete(args):
    sessions = scan_projects()
    filtered = apply_filters(sessions, args)
    if args.auto_empty:
        selected = [si for si in filtered if si.category == "empty"]
    else:
        selected = filtered
    if not selected:
        print("No sessions to delete.")
        return 0
    if confirm_deletion(selected, dry_run=args.dry_run):
        stats = delete_sessions(selected, dry_run=args.dry_run)
        print(f"\nDone: {stats['deleted']} deleted, {stats['failed']} failed, "
              f"{human_size(stats['bytes_freed'])} freed.")
    return 0


def cmd_list(args):
    list_projects()
    return 0


def cmd_sessions(args):
    list_sessions(args.path)
    return 0


def cmd_stats(args):
    sessions = scan_projects()
    filtered = apply_filters(sessions, args)
    print_stats(filtered)
    return 0


def cmd_table(args):
    """Non-interactive table output (old --no-fzf)."""
    sessions = scan_projects()
    filtered = apply_filters(sessions, args)
    if not filtered:
        print("No sessions.")
        return 0
    print(f"\n{'ID':<10}  {'Project':<28}  {'Date':<12}  {'Size':>6}  "
          f"{'Msgs':>6}  {'Cat':<6}  Description")
    print("─" * 120)
    for si in filtered:
        print(format_table_line(si))
    print(f"\n{len(filtered)} sessions, "
          f"{human_size(sum(s.total_size_bytes for s in filtered))} total")
    return 0


def cmd_rename(args):
    return 0 if rename_session(args.session_id, args.title) else 1


def cmd_rename_interactive(args):
    return 0 if rename_interactive(args.session_id) else 1


def cmd_search(args):
    results = search_user_prompts(args.query, use_regex=args.regex)
    if not results:
        print(f"No sessions matched: {args.query!r}")
        return 0
    selected = run_search_fzf(results)
    if not selected:
        print("Cancelled.")
        return 0
    path = selected["project_path"] or selected["project_name"]
    print(f"\nTo resume this session:")
    print(f"  cd {path}")
    print(f"  claude --resume {selected['session_id']}")
    return 0


def cmd_migrate(args):
    if args.here:
        target = os.path.normpath(os.path.abspath(os.getcwd()))
        print(f"{C_BOLD}Target (current directory):{C_RESET} {target}\n")
        source = select_source_fzf(target, show_all=args.all)
        if not source:
            print("No source selected. Cancelled.")
            return 1
        return 0 if migrate(source, target, dry_run=args.dry_run) else 1
    if not args.old_path or not args.new_path:
        print("Usage: session.py migrate OLD_PATH NEW_PATH  (or --here for picker)")
        return 1
    return 0 if migrate(args.old_path, args.new_path, dry_run=args.dry_run) else 1


def cmd_export(args):
    if args.path is None:
        source = select_source_fzf(target_path=None, show_all=True,
                                   header_prefix="Select project to export")
        if not source:
            print("No project selected.")
            return 1
        project_path = source
    else:
        project_path = os.path.normpath(os.path.abspath(args.path))
    return 0 if export_project(project_path, args.output, dry_run=args.dry_run) else 1


def cmd_import(args):
    target = args.target or os.getcwd()
    target = os.path.normpath(os.path.abspath(target))
    return 0 if import_project(args.archive, target,
                               dry_run=args.dry_run, conflict=args.conflict) else 1


def cmd_repair(args):
    return 0 if repair_project(args.path, dry_run=args.dry_run) else 1


def cmd_resume(args):
    return 0 if resume_session_by_id(args.session_id) else 1


def cmd_preview(args):
    handle_preview(args.session_id)
    return 0


def cmd_fzf_lines(args):
    emit_fzf_lines()
    return 0


def main():
    parser = argparse.ArgumentParser(
        prog="session.py",
        description="Claude Code session management — browse, delete, rename, search, migrate, export, import.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="cmd")

    p = sub.add_parser("browse", help="Interactive fzf browser (default)")
    _add_filter_args(p)
    p.add_argument("--auto-empty", action="store_true",
                   help="Auto-select all empty sessions")
    p.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("delete", help="Delete sessions (with filters)")
    _add_filter_args(p)
    p.add_argument("--auto-empty", action="store_true")
    p.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("list", help="List all projects with path status")

    p = sub.add_parser("sessions", help="List sessions for one project")
    p.add_argument("path", nargs="?", default=".", help="Project path (default: cwd)")

    p = sub.add_parser("stats", help="Summary statistics")
    _add_filter_args(p)

    p = sub.add_parser("table", help="Non-interactive table view")
    _add_filter_args(p)

    p = sub.add_parser("rename", help="Set a session's custom title")
    p.add_argument("session_id", help="Session UUID prefix")
    p.add_argument("title", help="New title")

    p = sub.add_parser("rename-interactive", help="Interactive rename (used by ctrl-r bind)")
    p.add_argument("session_id", help="Session UUID prefix")

    p = sub.add_parser("search", help="Search user prompts")
    p.add_argument("query", help="Search query")
    p.add_argument("--regex", action="store_true")

    p = sub.add_parser("migrate", help="Migrate sessions (moved folder, same machine)")
    p.add_argument("old_path", nargs="?", default=None)
    p.add_argument("new_path", nargs="?", default=None)
    p.add_argument("--here", action="store_true", help="Interactive picker, target=cwd")
    p.add_argument("--all", action="store_true", help="With --here: show all, not just missing")
    p.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("export", help="Pack sessions into portable .tar.gz")
    p.add_argument("path", nargs="?", default=None, help="Project path (or omit for picker)")
    p.add_argument("-o", "--output", default=None, metavar="FILE")
    p.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("import", help="Unpack archive and rewrite paths")
    p.add_argument("archive", help="Path to .tar.gz archive")
    p.add_argument("--target", default=None, help="Target project path (default: cwd)")
    p.add_argument("--conflict", choices=["skip", "overwrite", "abort"], default="skip")
    p.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("repair", help="Audit & fix orphaned/ghost sessions")
    p.add_argument("path", default=".", nargs="?")
    p.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("resume", help="Register session in history.jsonl for claude --resume")
    p.add_argument("session_id", help="Session UUID")

    p = sub.add_parser("preview", help="(internal) fzf preview callback")
    p.add_argument("session_id")

    p = sub.add_parser("fzf-lines", help="(internal) fzf reload callback")

    args = parser.parse_args()

    handlers = {
        "browse": cmd_browse, "delete": cmd_delete, "list": cmd_list,
        "sessions": cmd_sessions, "stats": cmd_stats, "table": cmd_table,
        "rename": cmd_rename, "rename-interactive": cmd_rename_interactive,
        "search": cmd_search, "migrate": cmd_migrate,
        "export": cmd_export, "import": cmd_import,
        "repair": cmd_repair, "resume": cmd_resume,
        "preview": cmd_preview, "fzf-lines": cmd_fzf_lines,
    }

    if args.cmd is None:
        # Default: browse with no filters
        class _Defaults:
            project = None
            category = None
            older_than = None
            sort = "date"
            auto_empty = False
            dry_run = False
        sys.exit(cmd_browse(_Defaults()))

    handler = handlers.get(args.cmd)
    if handler is None:
        parser.print_help()
        sys.exit(1)
    sys.exit(handler(args))


if __name__ == "__main__":
    main()
