#!/bin/bash
# tmux-exec.sh — Send command to tmux, wait for completion, capture output.
#
# Replaces the "sleep N && tmux capture-pane" pattern with instant
# completion detection via tmux wait-for.
#
# Usage:
#   tmux-exec.sh [--cwd <path>] <session> <command>
#   tmux-exec.sh claude-running-myproject "python train.py --epochs 10"
#   tmux-exec.sh --cwd /tmp claude-running-myproject "ls -la"
#
# CWD anchoring (NEW):
#   The pane is ALWAYS cd'd to a known-good directory before the command
#   runs. Resolution order:
#     1. --cwd <path>           (explicit flag, highest priority)
#     2. $TMUX_EXEC_CWD         (env var)
#     3. $PWD                   (cwd of whoever invoked this script)
#
#   For Claude Code agents, $PWD is the agent's primary working directory,
#   so this is automatically correct per-project without any hardcoding.
#   The cd is prepended to the command; if cd fails, the command is
#   skipped but the wait-for signal still fires so the script doesn't hang.
#
# The script:
#   1. Sends `cd <target> && { <command>; }` to the tmux session
#   2. Appends a tmux wait-for signal so we know when it finishes
#   3. Blocks until the command completes
#   4. Captures and prints the pane output

set -euo pipefail

# Parse optional --cwd flag
EXPLICIT_CWD=""
if [ "${1:-}" = "--cwd" ]; then
    if [ $# -lt 2 ]; then
        echo "tmux-exec: --cwd requires a path argument" >&2
        exit 1
    fi
    EXPLICIT_CWD="$2"
    shift 2
fi

if [ $# -lt 2 ]; then
    echo "Usage: tmux-exec.sh [--cwd <path>] <session> <command>" >&2
    exit 1
fi

SESSION="$1"
shift
COMMAND="$*"

# Resolve target cwd: --cwd > $TMUX_EXEC_CWD > $PWD
TARGET_CWD="${EXPLICIT_CWD:-${TMUX_EXEC_CWD:-$PWD}}"
RESOLVED_CWD="$(cd "$TARGET_CWD" 2>/dev/null && pwd)" || {
    echo "tmux-exec: cannot resolve target cwd: $TARGET_CWD" >&2
    exit 1
}

# Unique signal name to avoid collisions with concurrent commands
SIGNAL="claude-done-${SESSION}-$$"

# Quote the cwd safely so paths with spaces / special chars still work.
QUOTED_CWD="$(printf '%q' "$RESOLVED_CWD")"

# Prepend cd to a known-good directory before the user's command.
# Using `{ ...; }` groups the user's command so its exit status doesn't
# matter for the wait-for signal (the `;` before tmux wait-for fires
# the signal regardless of success/failure).
PAYLOAD="cd $QUOTED_CWD && { $COMMAND; }"

# Send command with completion signal
tmux send-keys -t "$SESSION" "$PAYLOAD; tmux wait-for -S $SIGNAL" Enter

# Block until the command signals completion
tmux wait-for "$SIGNAL"

# Capture pane output (last 50 lines for context)
tmux capture-pane -t "$SESSION" -p -S -50
