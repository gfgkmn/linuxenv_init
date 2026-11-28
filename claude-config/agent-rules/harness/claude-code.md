# Claude Code

Only what is specific to Claude Code on gfgkmn's machines.

## Tmux is the shared whiteboard

gfgkmn watches long work in tmux and may type there too. A hook (`hooks/enforce-tmux.sh`) rejects long-running commands outside tmux.

- Session name: `claude-running-<basename of the working directory>`.
- At a shell prompt, run and wait with `~/.claude/scripts/tmux-exec.sh <session> "<command>"`. Do not poll with `sleep` plus `capture-pane`; the hook blocks it.
- Send `cd <path>` as its own command first. If the project uses conda or a venv, activate it in the pane next, also as its own command. Look at the pane before sending anything, because gfgkmn may have acted.
- Keep the output visible: no `| tee` (it blocks Ctrl+C) and no `> file 2>&1` (it hides the output). To keep a log, use `tmux pipe-pane -t <session> -o 'cat >> <logfile>'` and turn it off afterwards.
- A long run must show progress: tqdm, `--verbose`, periodic prints.
- If the hook says "use tmux", run that same command in tmux. Do not split or rewrite it to get around the hook.
- SSH to a remote shell is still a shell prompt; `tmux-exec.sh` works there.

### A REPL in the pane

When the pane shows `In [N]:`, `(Pdb)`, `ipdb>` or `>>>`, and gfgkmn has asked you to work in it:

- Read with `~/.claude/scripts/tmux-capture.sh <session> [lines]` and send with plain `tmux send-keys`. `tmux-exec.sh` hangs in a REPL, because its wait signal needs a shell.
- Inspecting values, computing into new variables and stepping need no permission. Ask before keys that change state you cannot restore: deleting, overwriting files, installing, closing connections, remote writes.
- If gfgkmn has not asked you into the REPL, leave it alone.

## Hooks that act on you

- `audit_edit.py` may show an edit to gfgkmn for review. A rejection means stop and ask.
- `enforce-shot.sh` allows screen capture only through `~/.claude/scripts/cc-shot.sh`.
- `skill-gate.sh` asks gfgkmn before a plugin or skill is installed, or a new skill is written.
- `session-role.sh` adds the rule file for this session's role when the session starts.
- `cc-bridge-hook.sh` tells gfgkmn's Emacs when you stop.

The tmux and screenshot hooks only object or stay silent. They approve nothing; the normal permission flow decides. No hook checks the form of a reply.

## Subagents

- A subagent starts without your conversation, so the brief must hold everything it needs.
- `ml-runner` takes long training and evaluation runs; `emacs-probe` takes Emacs problems. Both are workers.

## Skills to reach for

- `ui-craft`: anything about how an interface looks, feels or moves.
- `step-back`: the long form of the step-back questions.
- `retro`: review recent corrections and turn them into checks (gfgkmn starts it).
