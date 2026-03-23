#!/usr/bin/env python
"""PreToolUse hook: open edit/write content in Emacs for audit.

Uses claude-audit.el minor mode in Emacs for a clean review experience:
  C-c C-c  Approve (auto-detects modifications for Write)
  C-c C-k  Reject

Edit/MultiEdit: split view — original file (left) + after version (right).
  Both windows have full syntax highlighting and LSP support.
Write: shows actual file content with proper extension (editable).
"""

import json
import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

IS_MACOS = sys.platform == "darwin"
EDITOR = os.environ.get("EDITOR", "vim")
AUDIT_MARKER = Path.home() / ".claude" / ".audit-enabled"


def is_audit_enabled() -> bool:
    return AUDIT_MARKER.exists()


# ── Build "after" content for Edit ─────────────────────────────────────────

def build_after_content(tool_input: dict) -> str:
    """Build the full file content after applying the edit."""
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
    """Build the full file content after applying all edits."""
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


# ── Window management ──────────────────────────────────────────────────────

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

def open_split_in_emacs(original_path: str, after_path: str):
    """Open original + after file in Emacs split view."""
    elisp = f'(claude-audit-open-split "{original_path}" "{after_path}")'
    tty = open("/dev/tty", "r")
    subprocess.run(
        ["emacsclient", "-c", "--eval", elisp],
        stdin=tty, check=True
    )
    tty.close()


def open_in_emacs(tmp_path: str):
    """Open single file in Emacs with claude-audit-mode."""
    tty = open("/dev/tty", "r")
    subprocess.run(["emacsclient", "-c", tmp_path], stdin=tty, check=True)
    tty.close()


def open_in_editor(tmp_path: str):
    """Open file in $EDITOR (fallback for non-emacs editors)."""
    tty = open("/dev/tty", "r")
    subprocess.run(shlex.split(EDITOR) + [tmp_path], stdin=tty, check=True)
    tty.close()


def is_emacs_editor() -> bool:
    return "emacs" in EDITOR.lower()


# ── Decision handling ──────────────────────────────────────────────────────

def read_decision(tmp_path: str) -> str:
    decision_file = tmp_path + ".decision"
    try:
        decision = Path(decision_file).read_text().strip()
        return decision if decision in ("approve", "change", "reject") else "unknown"
    except OSError:
        return "unknown"
    finally:
        try:
            os.unlink(decision_file)
        except OSError:
            pass


def handle_approve():
    print(json.dumps({"decision": "allow"}))


def handle_reject():
    print(json.dumps({
        "decision": "block",
        "reason": "Rejected by user during audit review"
    }))
    print("Rejected by user in audit review", file=sys.stderr)
    sys.exit(2)


def handle_edit_change(tool_input: dict, tmp_path: str):
    """User modified the 'after' version in split view — apply it directly."""
    user_content = Path(tmp_path).read_text()
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


def handle_write_change(tool_input: dict, tmp_path: str):
    """User modified Write content — apply their version."""
    user_content = Path(tmp_path).read_text()
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


# ── Fallback for non-Emacs editors ────────────────────────────────────────

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

    # For non-emacs editors, prepend the APPROVE line
    if not use_emacs:
        content = "# APPROVE (delete this line to BLOCK)\n#\n" + content

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=ext, prefix="claude-audit-", delete=False
    ) as f:
        f.write(content)
        tmp_path = os.path.realpath(f.name)

    try:
        hide_terminal()

        if use_emacs:
            if is_diff and file_path:
                # Split view: original (left) + after (right)
                real_file = os.path.realpath(file_path)
                open_split_in_emacs(real_file, tmp_path)
            else:
                # Write: single file view
                open_in_emacs(tmp_path)
        else:
            open_in_editor(tmp_path)

        show_terminal()

        if use_emacs:
            decision = read_decision(tmp_path)
            if decision == "approve":
                handle_approve()
            elif decision == "reject":
                handle_reject()
            elif decision == "change":
                if is_diff:
                    handle_edit_change(tool_input, tmp_path)
                else:
                    handle_write_change(tool_input, tmp_path)
            else:
                handle_reject()
                return
        else:
            handle_fallback_decision(tmp_path, content, tool_name, tool_input)

    except (subprocess.CalledProcessError, OSError, KeyboardInterrupt) as e:
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
