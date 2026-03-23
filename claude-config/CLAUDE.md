- When the task completes, echo "gfgkmn, my job is done" to alert the user to respond.

## Human-Agent Cooperation
- You work in a collaborative mode with the human. Do most tasks normally (file edits, searches, etc.), but run non-trivial commands (python, node, long bash processes) in tmux so the human can observe.
- Tmux session name: `claude-running-<project>` where `<project>` is the basename of the working directory (e.g., `claude-running-ml-pipeline`). This avoids conflicts when running multiple Claude instances.
- The tmux session is a shared whiteboard and running environment — the human may also use it to run things or leave output for you.
- When blocked or a task fails, state clearly in conversation what help is needed. Wait for the human to confirm "done" before continuing.
- Check tmux state before running new commands there, as the human may have acted.
- The tmux session has its own working directory. Always send `cd /target/path` as a separate `tmux send-keys` command before running commands that need a specific directory.

## Working Principles
- Default to short waits (1-2s) when checking command results, logs, or process output. Most tasks finish near-instantly. Only increase wait time when the task is genuinely long-running (model training, large data loads, builds).
- For time-consuming or hard-to-reverse tasks (data pipelines, training, deployments, migrations), always start at the smallest viable scale first — tiny data subset, 1 epoch, few rows. Verify correctness, then scale up incrementally. Never jump straight to full scale.
- **Think before coding.** Do not rush to write code. First discuss the plan, approach, and logic with the human. Only start coding after the human confirms they understand and agree with the plan.
- **Treat every failure as a signal.** Never blindly retry or guess. When something fails, stop and discuss with the human what went wrong and why. Only proceed when you are confident about the root cause and the fix.
- **Three strikes rule.** If three attempts at solving the same problem fail, stop immediately. Step back, rethink from first principles, and discuss with the human before trying anything else.

## macOS Shell Aliases & Environment
- `cat` → `bat`, `bat` → `/bin/cat` (swapped!)
- `grep` → `ggrep -i` (case-insensitive GNU grep)
- `sed` → `gsed` (GNU sed)
- `rm` → `rm-trash` (moves to trash instead of deleting)
- `python` is linked to `python3` — always use `python`, never `python3`
- `vim` → MacVim
- `ll` → `exa -alh -snew`
- `tree` → `tree -N`
- `td` → `tldr`
- `locate` → `glocate`
- Avoid using these aliased commands via Bash tool when dedicated tools (Read, Grep, Glob, Edit) are available
