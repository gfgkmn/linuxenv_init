# Project Rules

@.claude/cooperation.md
@.claude/environment.md

## Task Completion

When a task completes, echo `gfgkmn, my job is done` to alert the user.

## Mandatory Workflow Gates

- Before writing ANY code: output a numbered plan, then ask "Shall I proceed?" Do NOT write code until the user confirms.
- Before modifying ANY existing working code: (1) read the source, (2) explain to the user WHY the current code works, (3) propose changes, (4) wait for user approval. NEVER edit working code you have not researched.
- If the user rejects an edit (audit hook rejection): STOP immediately. Ask the user what was wrong. Do NOT attempt a variation.

## Tmux Requirement

Run non-trivial commands (python, node, builds, long bash processes) in tmux so the user can observe.
Session name: `claude-running-<project>` where `<project>` is the basename of the working directory.
Always `cd /target/path` as a separate `tmux send-keys` before running commands that need a specific directory.
Check tmux state before sending new commands — the user may have acted.
NEVER use `| tee` inside tmux — it blocks Ctrl+C.
For long-running tasks, ALWAYS ensure the command produces visible progress (tqdm, --verbose, --log-interval, periodic prints).

## Failure Protocol

- Default to short waits (1-2s) when checking command output. Only increase for genuinely long-running tasks.
- NEVER blindly retry or guess. When something fails, stop and discuss root cause with the user.
- Three failures on the same problem: STOP. Rethink from first principles and discuss with the user before trying again.

## Scale-Up Discipline

For time-consuming or hard-to-reverse tasks (training, data pipelines, deployments, migrations): always start at the smallest viable scale first. Verify correctness, then scale up. NEVER jump to full scale.

## Tool Preferences

- Prefer dedicated tools (Read, Grep, Glob, Edit) over shell aliases when available.
- Provide no more than three alternative approaches.
- When modifying code, make the minimal necessary edits.
- Suggest at most two verification checks per response.
