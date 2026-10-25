#!/bin/bash
# tmux-exec.sh — Send command to tmux, wait for completion, capture output.
#
# Replaces the "sleep N && tmux capture-pane" pattern with instant
# completion detection via tmux wait-for.
#
# Usage:
#   tmux-exec.sh [--cwd <path>] [--timeout <seconds>] <session> <command>
#   tmux-exec.sh claude-running-myproject "python train.py --epochs 10"
#   tmux-exec.sh --cwd /tmp claude-running-myproject "ls -la"
#   tmux-exec.sh --timeout 7200 claude-running-myproject "./long-train.sh"
#
# CWD anchoring:
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
#   1. Refuses to send while the pane is BUSY (see below)
#   2. Sends `cd <target> && { <command>; }` to the tmux session
#   3. Appends a tmux wait-for signal so we know when it finishes
#   4. Blocks until the command completes, OR until the timeout
#   5. Captures and prints the pane output
#
# WHY THE BUSY GATE EXISTS (added 2026-10-25):
#   `send-keys` types into whatever is reading the pane's tty. If the pane
#   is NOT at a shell prompt, the keystrokes go to the RUNNING PROGRAM's
#   stdin instead of the shell, so the `; tmux wait-for -S <signal>' tail
#   is never executed as a command -- and this script then blocks forever
#   on a signal that nobody will ever send. Four such jobs were found
#   wedged across projects on 2026-10-25, the oldest hung for 18 days,
#   each holding a `tmux wait-for' whose parent had long since exited.
#   The signal name embeds $$ so it never collides; the PANE is the
#   unguarded resource, and two concurrent senders (e.g. a backgrounded
#   call plus a foreground one on the same session) is all it takes.
#
#   Busy is detected two ways, because either alone has a blind spot:
#     - `pane_current_command' is not a shell -> something is running;
#     - the pane's shell has a CHILD process -> something is running even
#       when that something is itself a shell (a `bash script.sh').
#   Measured on this machine: an idle zsh pane reports `zsh' and has no
#   children, so neither test false-positives on a decorated prompt.
#
# EXIT CODES:
#   0    command ran, pane output printed
#   124  timed out waiting for the completion signal (output still printed)
#   125  refused: the pane was still busy after the grace period
#   126  no such tmux session
#
# TUNING (env, all seconds):
#   TMUX_EXEC_TIMEOUT      default 1800   how long to wait for completion
#   TMUX_EXEC_BUSY_GRACE   default 30     how long to wait for a free pane

set -euo pipefail

# Parse optional flags, in any order, before <session>.
EXPLICIT_CWD=""
EXPLICIT_TIMEOUT=""
while [ $# -gt 0 ]; do
    case "${1:-}" in
        --cwd)
            if [ $# -lt 2 ]; then
                echo "tmux-exec: --cwd requires a path argument" >&2
                exit 1
            fi
            EXPLICIT_CWD="$2"; shift 2 ;;
        --timeout)
            if [ $# -lt 2 ]; then
                echo "tmux-exec: --timeout requires a number of seconds" >&2
                exit 1
            fi
            EXPLICIT_TIMEOUT="$2"; shift 2 ;;
        *) break ;;
    esac
done

if [ $# -lt 2 ]; then
    echo "Usage: tmux-exec.sh [--cwd <path>] [--timeout <seconds>] <session> <command>" >&2
    exit 1
fi

SESSION="$1"
shift
COMMAND="$*"

TIMEOUT="${EXPLICIT_TIMEOUT:-${TMUX_EXEC_TIMEOUT:-1800}}"
BUSY_GRACE="${TMUX_EXEC_BUSY_GRACE:-30}"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "tmux-exec: no such tmux session: $SESSION" >&2
    echo "tmux-exec: create it first, e.g. tmux new-session -d -s $SESSION" >&2
    exit 126
fi

# Resolve target cwd: --cwd > $TMUX_EXEC_CWD > $PWD
TARGET_CWD="${EXPLICIT_CWD:-${TMUX_EXEC_CWD:-$PWD}}"
RESOLVED_CWD="$(cd "$TARGET_CWD" 2>/dev/null && pwd)" || {
    echo "tmux-exec: cannot resolve target cwd: $TARGET_CWD" >&2
    exit 1
}

# Is the pane running something?  Sets BUSY_WITH on success (= busy).
BUSY_WITH=""
pane_busy() {
    local cmd pane_pid kids
    BUSY_WITH=""
    cmd="$(tmux display-message -p -t "$SESSION" '#{pane_current_command}' 2>/dev/null || true)"
    case "$cmd" in
        zsh|bash|sh|fish|dash|ksh|tcsh|csh|"") ;;
        *) BUSY_WITH="$cmd"; return 0 ;;
    esac
    pane_pid="$(tmux display-message -p -t "$SESSION" '#{pane_pid}' 2>/dev/null || true)"
    [ -n "$pane_pid" ] || return 1
    kids="$(pgrep -P "$pane_pid" 2>/dev/null | head -1 || true)"
    [ -n "$kids" ] || return 1
    BUSY_WITH="$(ps -o command= -p "$kids" 2>/dev/null | head -1 | cut -c1-70)"
    [ -n "$BUSY_WITH" ] || BUSY_WITH="pid $kids"
    return 0
}

# Wait for a free pane rather than typing into a running program's stdin.
WAITED=0
while pane_busy; do
    if [ "$WAITED" -ge "$BUSY_GRACE" ]; then
        echo "tmux-exec: pane '$SESSION' is busy with: $BUSY_WITH" >&2
        echo "tmux-exec: refusing to send after ${BUSY_GRACE}s -- the keystrokes would go to that" >&2
        echo "tmux-exec: program's stdin, not the shell, and the completion signal would never" >&2
        echo "tmux-exec: fire (that is how jobs end up hung for days)." >&2
        echo "tmux-exec: wait for it, use another session, or raise TMUX_EXEC_BUSY_GRACE." >&2
        exit 125
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done

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

# Block until the command signals completion -- but BOUNDED.  `tmux
# wait-for' has no timeout of its own, and there is no portable bare
# `timeout' on macOS, so watch it from here.
tmux wait-for "$SIGNAL" &
WAIT_PID=$!
ELAPSED=0
TIMED_OUT=0
while kill -0 "$WAIT_PID" 2>/dev/null; do
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        TIMED_OUT=1
        kill "$WAIT_PID" 2>/dev/null || true
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
wait "$WAIT_PID" 2>/dev/null || true

if [ "$TIMED_OUT" = 1 ]; then
    # Two very different failures wear the same timeout, so say which.
    if pane_busy; then
        echo "tmux-exec: TIMED OUT after ${TIMEOUT}s; pane still busy with: $BUSY_WITH" >&2
        echo "tmux-exec: the command is probably just slower than the timeout -- watch the" >&2
        echo "tmux-exec: pane, or re-run with --timeout / TMUX_EXEC_TIMEOUT raised." >&2
    else
        echo "tmux-exec: TIMED OUT after ${TIMEOUT}s; pane is IDLE and the signal never fired." >&2
        echo "tmux-exec: the payload was swallowed -- it never ran as a command. Signal was" >&2
        echo "tmux-exec: $SIGNAL. Check the pane: the command text may be sitting in some" >&2
        echo "tmux-exec: program's stdin." >&2
    fi
    tmux capture-pane -t "$SESSION" -p -S -50
    exit 124
fi

# Capture pane output (last 50 lines for context)
tmux capture-pane -t "$SESSION" -p -S -50
