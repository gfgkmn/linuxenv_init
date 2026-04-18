#!/bin/bash
# tmux-capture.sh — Read current pane contents without sending any keys.
#
# Use this for Manual Trigger mode (interactive REPLs like IPython, PDB,
# ipdb, Python >>>) where tmux-exec.sh cannot be used: REPLs have no
# shell exit, so the "; tmux wait-for -S <signal>" payload would be
# typed into the REPL and either error or hang.
#
# Usage:
#   tmux-capture.sh <session> [lines]
#   tmux-capture.sh claude-running-myproject
#   tmux-capture.sh claude-running-myproject 120

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: tmux-capture.sh <session> [lines]" >&2
    exit 1
fi

SESSION="$1"
LINES="${2:-50}"

tmux capture-pane -t "$SESSION" -p -S "-$LINES"
