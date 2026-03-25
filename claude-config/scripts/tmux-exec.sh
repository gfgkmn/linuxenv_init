#!/bin/bash
# tmux-exec.sh — Send command to tmux, wait for completion, capture output.
#
# Replaces the "sleep N && tmux capture-pane" pattern with instant
# completion detection via tmux wait-for.
#
# Usage:
#   tmux-exec.sh <session> <command>
#   tmux-exec.sh claude-running-myproject "python train.py --epochs 10"
#
# The script:
#   1. Sends the command to the tmux session
#   2. Appends a tmux wait-for signal so we know when it finishes
#   3. Blocks until the command completes
#   4. Captures and prints the pane output

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: tmux-exec.sh <session> <command>" >&2
    exit 1
fi

SESSION="$1"
shift
COMMAND="$*"

# Unique signal name to avoid collisions with concurrent commands
SIGNAL="claude-done-${SESSION}-$$"

# Send command with completion signal
# The semicolon chains: run command, THEN signal done
tmux send-keys -t "$SESSION" "$COMMAND; tmux wait-for -S $SIGNAL" Enter

# Block until the command signals completion
tmux wait-for "$SIGNAL"

# Capture pane output (last 50 lines for context)
tmux capture-pane -t "$SESSION" -p -S -50
