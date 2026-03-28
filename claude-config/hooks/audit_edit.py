#!/usr/bin/env python
"""PreToolUse hook: audit edits based on CLAUDE_AUDIT_MODE env var.

Modes (session-scoped via env var):
  permissive — allow all edits, no review
  audit      — open in Emacs for review (split view, diff highlights)
  strict     — terminal prompt: y/n/a/e per edit

Transports for audit mode:
  - emacsclient (local): split view via claude-audit-open-split
  - rmate (remote): sends file via rmate --wait with metadata

Strict mode prompt:
  y — allow this edit
  n — reject (prompts for reason)
  a — switch to permissive for rest of session
  e — open in Emacs audit for this edit
"""

import json
import os
import shlex
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

IS_MACOS = sys.platform == "darwin"
EDITOR = os.environ.get("EDITOR", "vim")

# Mode file — project-scoped via cwd, read on every hook invocation
AUDIT_MODE_FILE = Path.cwd() / ".claude" / ".audit-mode"

# Sentinel line used to encode decision in file content (for rmate transport)
DECISION_SENTINEL = "# __CLAUDE_AUDIT_DECISION__:"


# ── Hook response helpers ─────────────────────────────────────────────────

def hook_allow(reason: str = "approved by audit hook"):
    """Print the hookSpecificOutput JSON that Claude Code expects for allow."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason
        }
    }))


def hook_deny(reason: str = "Rejected by user during audit review"):
    """Print the hookSpecificOutput JSON that Claude Code expects for deny."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason
        }
    }))


# ── Mode detection ────────────────────────────────────────────────────────

def get_audit_mode() -> str:
    """Get current audit mode from file. Read on every invocation."""
    try:
        mode = AUDIT_MODE_FILE.read_text().strip()
        if mode in ("permissive", "audit", "strict"):
            return mode
    except OSError:
        pass
    return "permissive"


def is_emacs_editor() -> bool:
    return "emacsclient" in EDITOR.lower() or (
        "emacs" in EDITOR.lower() and "rmate" not in EDITOR.lower()
    )


def is_rmate_editor() -> bool:
    return "rmate" in EDITOR.lower()


def elisp_quote(path: str) -> str:
    """Escape a string for safe interpolation into an Elisp double-quoted string."""
    return path.replace("\\", "\\\\").replace('"', '\\"')


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
    """Check claude-audit-open-in setting from Emacs."""
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
    elisp = f'(claude-audit-open-split "{elisp_quote(original_path)}" "{elisp_quote(after_path)}")'
    mode = get_emacs_audit_mode()

    if mode == "workspace":
        subprocess.run(["emacsclient", "--eval", elisp], capture_output=True)
        _poll_for_decision(after_path)
    else:
        tty = open("/dev/tty", "r")
        subprocess.run(
            ["emacsclient", "-c", "--eval", elisp],
            stdin=tty, check=True
        )
        tty.close()


def open_in_emacs(tmp_path: str):
    mode = get_emacs_audit_mode()

    if mode == "workspace":
        subprocess.run(
            ["emacsclient", "--eval", f'(find-file "{elisp_quote(tmp_path)}")'],
            capture_output=True
        )
        _poll_for_decision(tmp_path)
    else:
        tty = open("/dev/tty", "r")
        subprocess.run(["emacsclient", "-c", tmp_path], stdin=tty, check=True)
        tty.close()


def _poll_for_decision(tmp_path: str, timeout: int = 600):
    decision_file = tmp_path + ".decision"
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(decision_file):
            return
        time.sleep(0.5)
    raise TimeoutError(f"Audit decision timeout after {timeout}s")


def open_rmate_audit(tmp_path: str, original_path: str, tool_name: str):
    hostname = socket.gethostname()
    try:
        ip = socket.gethostbyname(hostname)
    except socket.gaierror:
        ip = hostname

    display_name = f"claude-audit||{hostname}||{ip}||{original_path}||{tool_name}"

    tty = open("/dev/tty", "r")
    subprocess.run(
        ["rmate", "--wait", "-m", display_name, tmp_path],
        stdin=tty, timeout=600, check=True
    )
    tty.close()


def open_in_editor(tmp_path: str):
    tty = open("/dev/tty", "r")
    subprocess.run(shlex.split(EDITOR) + [tmp_path], stdin=tty, check=True)
    tty.close()



# ── Decision handling ──────────────────────────────────────────────────────

def parse_decision(raw: str) -> tuple[str, str]:
    if "||" in raw:
        decision, reason = raw.split("||", 1)
        return decision.strip(), reason.strip()
    return raw.strip(), ""


def read_decision_file(tmp_path: str) -> tuple[str, str]:
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
    content = Path(tmp_path).read_text()
    stripped = content.lstrip()
    if stripped.startswith(DECISION_SENTINEL):
        sentinel_start = len(content) - len(stripped)
        first_nl = content.index("\n", sentinel_start)
        decision_line = content[sentinel_start:first_nl].strip()
        raw_decision = decision_line.split(":", 1)[1].strip()
        remaining = content[first_nl + 1:]
        decision, reason = parse_decision(raw_decision)
        if decision in ("approve", "change", "reject"):
            return decision, reason, remaining
    return "reject", "", content


def handle_approve():
    hook_allow("approved by audit hook")


def handle_reject(reason: str = ""):
    if reason:
        msg = f"Rejected by user: {reason}"
    else:
        msg = "Rejected by user during audit review"
    hook_deny(msg)
    print(msg, file=sys.stderr)
    sys.exit(2)


def handle_edit_change(tool_input: dict, tmp_path: str, content_override: str = None):
    user_content = content_override if content_override is not None else Path(tmp_path).read_text()
    file_path = tool_input.get("file_path", "?")
    try:
        Path(file_path).write_text(user_content)
        hook_deny(
            f"User revised the edit during audit and applied to {file_path}. "
            f"The file now contains the user's version."
        )
    except OSError as e:
        hook_deny(f"User revised content but write failed: {e}")
    print(f"User revised content during audit for {file_path}", file=sys.stderr)
    sys.exit(2)


def handle_write_change(tool_input: dict, tmp_path: str, content_override: str = None):
    user_content = content_override if content_override is not None else Path(tmp_path).read_text()
    file_path = tool_input.get("file_path", "?")
    try:
        Path(file_path).write_text(user_content)
        hook_deny(
            f"User revised content during audit and applied to {file_path}. "
            f"User's version:\n\n{user_content}"
        )
    except OSError as e:
        hook_deny(f"User revised content but write failed: {e}")
    print(f"User revised content during audit for {file_path}", file=sys.stderr)
    sys.exit(2)


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


# ── Audit mode: Emacs review ──────────────────────────────────────────────

def run_audit_mode(tool_name, tool_input, file_path, content, is_diff, ext, tmp_path):
    """Full Emacs audit review flow."""
    use_emacs = is_emacs_editor()
    use_rmate = is_rmate_editor()

    # For plain editors, prepend the APPROVE line
    if not use_emacs and not use_rmate:
        Path(tmp_path).write_text("# APPROVE (delete this line to BLOCK)\n#\n" + content)

    try:
        if use_emacs:
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

        elif use_rmate:
            original_path = os.path.abspath(file_path) if file_path else ""
            open_rmate_audit(tmp_path, original_path, tool_name)

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

        else:
            open_in_editor(tmp_path)
            handle_fallback_decision(tmp_path,
                                      "# APPROVE (delete this line to BLOCK)\n#\n" + content,
                                      tool_name, tool_input)

    except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
            OSError, KeyboardInterrupt) as e:
        if use_emacs:
            show_terminal()
        hook_deny(f"Editor error: {e}")
        print(f"Editor error: {e}", file=sys.stderr)
        sys.exit(2)


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return

    mode = get_audit_mode()

    if mode != "audit":
        return

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")
    ext = get_file_extension(tool_input)

    if tool_name == "Edit":
        content = build_after_content(tool_input)
        is_diff = True
    elif tool_name == "MultiEdit":
        content = build_multiedit_after_content(tool_input)
        is_diff = True
    elif tool_name == "Write":
        content = tool_input.get("content", "")
        is_diff = bool(file_path) and Path(file_path).exists()
    else:
        return

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=ext, prefix="claude-audit-", delete=False
    ) as f:
        f.write(content)
        tmp_path = os.path.realpath(f.name)

    try:
        run_audit_mode(tool_name, tool_input, file_path, content, is_diff, ext, tmp_path)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
