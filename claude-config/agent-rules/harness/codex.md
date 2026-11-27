# Codex

Only what is specific to Codex on gfgkmn's machines.

- The Claude Code hooks are not active here. Nothing blocks a long command outside tmux, and nothing reviews an edit. The tmux rule and the boundary hold by your own discipline; the sandbox and approval policy in `~/.codex/config.toml` are the real limit.
- Long-running commands go in the tmux session `claude-running-<basename of the working directory>` so gfgkmn can watch: `~/.claude/scripts/tmux-exec.sh <session> "<command>"`. No `| tee` (it blocks Ctrl+C) and no `> file 2>&1` (it hides the output).
- Skills in `~/.codex/skills` are shared with Claude Code. Claude Code's slash commands appear here as skills.
