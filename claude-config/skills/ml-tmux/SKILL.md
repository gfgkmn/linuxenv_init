---
name: ml-tmux
description: Use tmux session "claude-test" for machine learning projects. When doing ML work (training, evaluation, data processing, experiments), run commands in the tmux session, monitor output, and report results back to the human. Use when the user mentions ML, training, experiments, or invokes /ml-tmux.
argument-hint: [command-or-task]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# ML Tmux Runner

You are operating in ML experiment mode. All compute-heavy commands (training, evaluation, data processing, plotting) MUST run inside the tmux session `claude-test`.

## Workflow

### 1. Ensure tmux session exists
Before running any command, check if the session exists and create it if not:
```bash
tmux has-session -t claude-test 2>/dev/null || tmux new-session -d -s claude-test
```

### 2. Run commands in tmux
Use `tmux send-keys` to execute commands inside the session:
```bash
tmux send-keys -t claude-test 'your-command-here' Enter
```

### 3. Capture and show output
After a command runs, capture the tmux pane content to check results:
```bash
tmux capture-pane -t claude-test -p -S -50
```
Use `-S -N` to capture the last N lines. Adjust as needed for longer outputs.

### 4. Wait for long-running commands
For training or long tasks, periodically check if the process is still running:
```bash
tmux send-keys -t claude-test '' ''  # no-op to refresh
tmux capture-pane -t claude-test -p -S -30
```
Report intermediate progress (loss, epoch, metrics) back to the human as it appears.

### 5. Handle virtual environments
If the ML project uses conda or venv, activate it inside the tmux session first:
```bash
tmux send-keys -t claude-test 'conda activate env-name' Enter
```

## Rules
- **NEVER** run ML training/eval commands directly in Bash — always route through tmux `claude-test`
- **DO** use direct Bash for quick non-compute tasks (file listing, git, pip freeze)
- **ALWAYS** capture and summarize output for the human after commands complete
- **REPORT** key metrics (loss, accuracy, F1, etc.) in a clear summary format
- If `$ARGUMENTS` is provided, treat it as the command or task to run immediately in the tmux session
