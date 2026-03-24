#!/usr/bin/env python
"""PreToolUse hook: open edit/write content in Emacs for audit.

Supports two transports:
  - emacsclient (local): split view via claude-audit-open-split
  - rmate (remote): sends file via rmate --wait with metadata in display-name

Uses claude-audit.el minor mode in Emacs for a clean review experience:
  C-c C-c  Approve (auto-detects modifications)
  C-c C-k  Reject
  C-c C-v  Toggle diff/focus view
  ]c / [c  Navigate changes

Edit/MultiEdit: split view — original file (left) + after version (right).
Write: shows actual file content with proper extension (editable).
"""

import json
import os
import shlex
import socket
import subprocess
import sys
import tempfile
from pathlib import Path

IS_MACOS = sys.platform == "darwin"
EDITOR = os.environ.get("EDITOR", "vim")
AUDIT_MARKER = Path.home() / ".claude" / ".audit-enabled"

# Sentinel line used to encode decision in file content (for rmate transport)
DECISION_SENTINEL = "# __CLAUDE_AUDIT_DECISION__:"


def is_audit_enabled() -> bool:
    return AUDIT_MARKER.exists()


# ── Editor detection ──────────────────────────────────────────────────────

def is_emacs_editor() -> bool:
    return "emacsclient" in EDITOR.lower() or (
        "emacs" in EDITOR.lower() and "rmate" not in EDITOR.lower()
    )


def is_rmate_editor() -> bool:
    return "rmate" in EDITOR.lower()


# ── Build "after" content for Edit ─────────────────────────────────────────

def build_after_content(tool_input: dict) -> str:
    file_path = tool_input.get("file_path", "?")
    old_string = tool_input.get("old_string", "")
    new_string = tool_input.get("new_string", "")
    replace_all = tool_input.get("replace_all", False)

    try:
        content = Path(file_path).read_text()
    except OSError:
        return new_string

    if replace_all:
        return content.replace(old_string, new_string)
    else:
        return content.replace(old_string, new_string, 1)


def build_multiedit_after_content(tool_input: dict) -> str:
    file_path = tool_input.get("file_path", "?")
    edits = tool_input.get("edits", [])

    try:
        content = Path(file_path).read_text()
    except OSError:
        return ""

    for edit in edits:
        old = edit.get("old_string", "")
        new = edit.get("new_string", "")
        content = content.replace(old, new, 1)

    return content


def get_file_extension(tool_input: dict) -> str:
    file_path = tool_input.get("file_path", "")
    if file_path:
        ext = Path(file_path).suffix
        if ext:
            return ext
    return ".txt"


# ── Window management (macOS only) ────────────────────────────────────────

def hide_terminal():
    if IS_MACOS:
        subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to set visible of process "iTerm2" to false'],
            capture_output=True
        )


def show_terminal():
    if IS_MACOS:
        subprocess.run(
            ["osascript", "-e", 'tell application "iTerm2" to activate'],
            capture_output=True
        )


# ── Editor launch ──────────────────────────────────────────────────────────

def get_emacs_audit_mode() -> str:
    """Check claude-audit-open-in setting from Emacs. Returns 'frame' or 'workspace'."""
    try:
        result = subprocess.run(
            ["emacsclient", "--eval", "(symbol-value 'claude-audit-open-in)"],
            capture_output=True, text=True, timeout=5
        )
        val = result.stdout.strip()
        if val == "workspace":
            return "workspace"
    except (subprocess.TimeoutExpired, OSError):
        pass
    return "frame"


def open_split_in_emacs(original_path: str, after_path: str):
    """Open original + after file in Emacs split view via emacsclient."""
    elisp = f'(claude-audit-open-split "{original_path}" "{after_path}")'
    mode = get_emacs_audit_mode()

    if mode == "workspace":
        # Workspace mode: non-blocking eval, then poll for decision
        subprocess.run(
            ["emacsclient", "--eval", elisp],
            capture_output=True
        )
        # Poll for decision file
        _poll_for_decision(after_path)
    else:
        # Frame mode: blocking -c flag
        tty = open("/dev/tty", "r")
        subprocess.run(
            ["emacsclient", "-c", "--eval", elisp],
            stdin=tty, check=True
        )
        tty.close()


def open_in_emacs(tmp_path: str):
    """Open single file in Emacs with claude-audit-mode via emacsclient."""
    mode = get_emacs_audit_mode()

    if mode == "workspace":
        elisp = f'(progn (claude-audit-open-split nil "{tmp_path}"))'
        subprocess.run(
            ["emacsclient", "--eval", f'(find-file "{tmp_path}")'],
            capture_output=True
        )
        _poll_for_decision(tmp_path)
    else:
        tty = open("/dev/tty", "r")
        subprocess.run(["emacsclient", "-c", tmp_path], stdin=tty, check=True)
        tty.close()


def _poll_for_decision(tmp_path: str, timeout: int = 600):
    """Poll for the .decision file until it appears or timeout."""
    import time
    decision_file = tmp_path + ".decision"
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(decision_file):
            return
        time.sleep(0.5)
    raise TimeoutError(f"Audit decision timeout after {timeout}s")


def open_rmate_audit(tmp_path: str, original_path: str, tool_name: str):
    """Open file via rmate --wait with audit metadata in display-name."""
    hostname = socket.gethostname()
    try:
        ip = socket.gethostbyname(hostname)
    except socket.gaierror:
        ip = hostname

    # Use || delimiter to avoid conflicts with colons in paths
    display_name = f"claude-audit||{hostname}||{ip}||{original_path}||{tool_name}"

    tty = open("/dev/tty", "r")
    subprocess.run(
        ["rmate", "--wait", "-m", display_name, tmp_path],
        stdin=tty, timeout=600, check=True
    )
    tty.close()


def open_in_editor(tmp_path: str):
    """Open file in $EDITOR (fallback for non-emacs/non-rmate editors)."""
    tty = open("/dev/tty", "r")
    subprocess.run(shlex.split(EDITOR) + [tmp_path], stdin=tty, check=True)
    tty.close()


# ── Decision handling ──────────────────────────────────────────────────────

def parse_decision(raw: str) -> tuple[str, str]:
    """Parse decision string, which may include a reason.

    Format: 'approve' or 'reject||reason text'
    Returns (decision, reason).
    """
    if "||" in raw:
        decision, reason = raw.split("||", 1)
        return decision.strip(), reason.strip()
    return raw.strip(), ""


def read_decision_file(tmp_path: str) -> tuple[str, str]:
    """Read decision from .decision file (emacsclient transport).

    Returns (decision, reason).
    """
    decision_file = tmp_path + ".decision"
    try:
        raw = Path(decision_file).read_text().strip()
        decision, reason = parse_decision(raw)
        if decision in ("approve", "change", "reject"):
            return decision, reason
        return "unknown", ""
    except OSError:
        return "unknown", ""
    finally:
        try:
            os.unlink(decision_file)
        except OSError:
            pass


def read_rmate_decision(tmp_path: str) -> tuple[str, str, str]:
    """Read decision from file content sentinel (rmate transport).

    Returns (decision, reason, remaining_content).
    rmate may prepend whitespace/newlines, so we strip before checking.
    """
    content = Path(tmp_path).read_text()
    # Strip leading whitespace — rmate protocol may prepend \n
    stripped = content.lstrip()
    if stripped.startswith(DECISION_SENTINEL):
        first_nl = stripped.index("\n")
        decision_line = stripped[:first_nl].strip()
        raw_decision = decision_line.split(":", 1)[1].strip()
        remaining = stripped[first_nl + 1:]
        decision, reason = parse_decision(raw_decision)
        if decision in ("approve", "change", "reject"):
            return decision, reason, remaining
    return "reject", "", content


def handle_approve():
    print(json.dumps({"decision": "allow"}))


def handle_reject(reason: str = ""):
    if reason:
        msg = f"Rejected by user: {reason}"
    else:
        msg = "Rejected by user during audit review"
    print(json.dumps({
        "decision": "block",
        "reason": msg
    }))
    print(msg, file=sys.stderr)
    sys.exit(2)


def handle_edit_change(tool_input: dict, tmp_path: str, content_override: str = None):
    """User modified the 'after' version — apply it directly."""
    user_content = content_override if content_override is not None else Path(tmp_path).read_text()
    file_path = tool_input.get("file_path", "?")
    try:
        Path(file_path).write_text(user_content)
        print(json.dumps({
            "decision": "block",
            "reason": (
                f"User revised the edit during audit and applied to {file_path}. "
                f"The file now contains the user's version."
            )
        }))
    except OSError as e:
        print(json.dumps({
            "decision": "block",
            "reason": f"User revised content but write failed: {e}"
        }))
    print(f"User revised content during audit for {file_path}", file=sys.stderr)
    sys.exit(2)


def handle_write_change(tool_input: dict, tmp_path: str, content_override: str = None):
    """User modified Write content — apply their version."""
    user_content = content_override if content_override is not None else Path(tmp_path).read_text()
    file_path = tool_input.get("file_path", "?")
    try:
        Path(file_path).write_text(user_content)
        print(json.dumps({
            "decision": "block",
            "reason": (
                f"User revised content during audit and applied to {file_path}. "
                f"User's version:\n\n{user_content}"
            )
        }))
    except OSError as e:
        print(json.dumps({
            "decision": "block",
            "reason": f"User revised content but write failed: {e}"
        }))
    print(f"User revised content during audit for {file_path}", file=sys.stderr)
    sys.exit(2)


# ── Fallback for non-Emacs/non-rmate editors ─────────────────────────────

def handle_fallback_decision(tmp_path: str, original_content: str,
                              tool_name: str, tool_input: dict):
    result = Path(tmp_path).read_text()

    if "# APPROVE" not in result:
        handle_reject()
        return

    if result.strip() == original_content.strip():
        handle_approve()
    elif tool_name == "Write":
        handle_write_change(tool_input, tmp_path)
    else:
        handle_approve()


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        print(json.dumps({"decision": "allow"}))
        return

    if not is_audit_enabled():
        print(json.dumps({"decision": "allow"}))
        return

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")

    use_emacs = is_emacs_editor()
    use_rmate = is_rmate_editor()
    ext = get_file_extension(tool_input)

    if tool_name == "Edit":
        content = build_after_content(tool_input)
        is_diff = True
    elif tool_name == "MultiEdit":
        content = build_multiedit_after_content(tool_input)
        is_diff = True
    elif tool_name == "Write":
        content = tool_input.get("content", "")
        is_diff = False
    else:
        print(json.dumps({"decision": "allow"}))
        return

    # For plain editors (not emacs/rmate), prepend the APPROVE line
    if not use_emacs and not use_rmate:
        content = "# APPROVE (delete this line to BLOCK)\n#\n" + content

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=ext, prefix="claude-audit-", delete=False
    ) as f:
        f.write(content)
        tmp_path = os.path.realpath(f.name)

    try:
        if use_emacs:
            # ── emacsclient transport ──
            hide_terminal()
            if is_diff and file_path:
                real_file = os.path.realpath(file_path)
                open_split_in_emacs(real_file, tmp_path)
            else:
                open_in_emacs(tmp_path)
            show_terminal()

            decision, reason = read_decision_file(tmp_path)
            if decision == "approve":
                handle_approve()
            elif decision == "reject":
                handle_reject(reason)
            elif decision == "change":
                if is_diff:
                    handle_edit_change(tool_input, tmp_path)
                else:
                    handle_write_change(tool_input, tmp_path)
            else:
                handle_reject()
                return

        elif use_rmate:
            # ── rmate transport ──
            original_path = os.path.abspath(file_path) if file_path else ""
            open_rmate_audit(tmp_path, original_path, tool_name)

            # rmate --wait returned — read decision from file content
            decision, reason, remaining = read_rmate_decision(tmp_path)
            if decision == "approve":
                handle_approve()
            elif decision == "reject":
                handle_reject(reason)
            elif decision == "change":
                if is_diff:
                    handle_edit_change(tool_input, tmp_path, content_override=remaining)
                else:
                    handle_write_change(tool_input, tmp_path, content_override=remaining)
            else:
                handle_reject()
                return

        else:
            # ── Fallback editor ──
            open_in_editor(tmp_path)
            handle_fallback_decision(tmp_path, content, tool_name, tool_input)

    except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
            OSError, KeyboardInterrupt) as e:
        if use_emacs:
            show_terminal()
        print(json.dumps({
            "decision": "block",
            "reason": f"Editor error: {e}"
        }))
        print(f"Editor error: {e}", file=sys.stderr)
        sys.exit(2)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
