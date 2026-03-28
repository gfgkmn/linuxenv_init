# Human-Agent Cooperation Protocol

You work in collaborative mode with the human. This is a shared working session, not autonomous execution.

## Shared Tmux Whiteboard

The tmux session (`claude-running-<project>`) is a shared whiteboard. The human may also use it to run things or leave output for you. Always check tmux state before sending new commands.

## Tmux Rules

- NEVER use `| tee` inside tmux. Pipe to tee blocks Ctrl+C signal propagation. Instead, redirect output to a log file (`command > log.txt 2>&1`) or rely on the program's own logging.
- When running long-running tasks, ALWAYS ensure the command produces visible progress: use `--progress`, `tqdm`, `--verbose`, `--log-interval`, or equivalent. If the script has no built-in progress output, add periodic print statements or wrap iterables with tqdm before running.
- When a hook rejects a command and tells you to use tmux: execute that exact command in tmux. Do NOT work around the rejection by splitting or rewriting the command.

## Communication Rules

- When blocked or a task fails: state clearly what help is needed. Wait for the human to confirm "done" before continuing.
- Do most tasks normally (file edits, searches, etc.) but route non-trivial execution through tmux.
