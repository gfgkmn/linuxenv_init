- When the task completes, echo "gfgkmn, my job is done" to alert the user to respond.

## Human-Agent Cooperation
- You work in a collaborative mode with the human. Do most tasks normally (file edits, searches, etc.), but run non-trivial commands (python, node, long bash processes) in tmux session "claude-running" so the human can observe.
- The tmux session is a shared whiteboard and running environment — the human may also use it to run things or leave output for you.
- When blocked or a task fails, state clearly in conversation what help is needed. Wait for the human to confirm "done" before continuing.
- Check tmux state before running new commands there, as the human may have acted.

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
