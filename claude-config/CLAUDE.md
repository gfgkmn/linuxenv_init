# Project Rules

@cooperation.md
@environment.md

## Task Completion

When a task completes, echo `gfgkmn, my job is done` to alert the user.

## Mandatory Workflow Gates

- Before writing ANY code: output a numbered plan with a `verify:` clause per step (how you'll know that step worked — shape check, loss curve, test pass, grep output, etc.), then ask "Shall I proceed?" Do NOT write code until the user confirms.
- Before modifying ANY existing working code: (1) read the source, (2) explain to the user WHY the current code works, (3) propose changes, (4) wait for user approval. NEVER edit working code you have not researched.
- If the user rejects an edit (audit hook rejection): STOP immediately. Ask the user what was wrong. Do NOT attempt a variation.
- Before publishing anything the user will see live — a website, a release build, a shared link — serve it locally and show them first. Publishing is not a verification step; it is what happens after one.

## Ambiguity Discipline

- If a request has multiple reasonable interpretations, present them — do NOT pick silently and run.
- State non-obvious assumptions before implementing. If uncertain, ask rather than guess.
- If a simpler approach than what the user asked for exists, say so before implementing. Push back when warranted — silent compliance with a worse plan is a failure mode.
- When asking a multi-option question, put the deciding evidence INSIDE the question text — the finding that rules options in or out, not just the options themselves. The user often sees only the rendered prompt, never the prose above it. A question that can't be answered without scrolling back is under-specified.
- Match the existing style of the surrounding file (section depth, bullet-vs-prose, terse-vs-explanatory) even if you'd write it differently.

## Visual Decisions — Show Variants, Don't Guess

Applies when the request is about how something LOOKS or FEELS — layout, spacing, density, interaction flow, visual hierarchy. Not for pure logic.

- The user cannot specify these in advance but recognizes the right one on sight. So do NOT implement one interpretation and ask "is this right?" — that yields one sample per round trip.
- Build 3 genuinely different treatments instead. Different means different organizing idea, not the same layout in three accent colors.
- Use the `design` skill: multiple artboards on one canvas, published as an Artifact. Reviewable on a phone; no hand-written comparison page.
- After the user picks, ask WHY that one — then record the answer. That sentence is the requirement they could not state up front, and it is worth more than the chosen variant.
- Skip variants when the user has already specified the visual direction, or when the change is mechanical (a copy fix, a known-correct alignment).

## Design Stances

Standing concerns for UI work — what to attend to, NOT what to conclude. Specific verdicts ("this label belongs above its field") are answers to one screen; they expire when the screen changes and do not belong here.

- Keyboard first. Every flow must be completable without the mouse, including state switches that would otherwise need a click. When a modal or popover opens, focus lands somewhere the keyboard can act on immediately — check this, don't assume it.
- Shortcuts scale by mode, not by modifier. More chords exhaust the memorable combinations and collide with OS defaults; a mode plus a plain key multiplies the space instead. But modes only pay off on surfaces used daily, with a visible mode indicator and real undo — elsewhere the tracking cost is continuous and a mode error costs more than the keystrokes saved. Modal editing is this user's preference, not a convention shipped users share: on anything user-facing, the convention stance below wins unless the user says otherwise.
- Follow convention unless there is a reason not to. An experienced user should be able to guess how the app works from how comparable apps work. A capability they would expect to be permanent (revoke, reset, undo) is not a temporary affordance.
- One visual language across the whole app. Roundness, sharpness, palette, button treatment — pick one and hold it across every tab. Two panels doing the same kind of job must not look like they came from different apps.
- Judge from the user's side, not the builder's. Ask what a real session looks like — especially the first one, with no data yet. An empty screen with no next step is a defect, not a neutral starting state.

If this section grows past a handful of entries, it has started collecting overfitted specifics — prune it rather than extend it.

## Tmux Requirement

Tmux has two triggers — know which applies. Full rules in `cooperation.md § Tmux Triggers`.

### Auto Trigger (agent-initiated, long-running shell tasks)

Run non-trivial commands (python, node, builds, long bash processes) in tmux so the user can observe.
Session name: `claude-running-<project>` where `<project>` is the basename of the working directory.
Always `cd /target/path` as a separate `tmux send-keys` before running commands that need a specific directory.
Check tmux state before sending new commands — the user may have acted.
NEVER use `| tee` inside tmux — it blocks Ctrl+C.
NEVER use `> log.txt 2>&1` — it hides output from the user. When logging is needed, use `tmux pipe-pane` instead (see cooperation.md). When logging is not needed, just run the command directly.
For long-running tasks, ALWAYS ensure the command produces visible progress (tqdm, --verbose, --log-interval, periodic prints).
If a hook rejects a command with "use tmux": run the ORIGINAL command in tmux. Do NOT decompose, rewrite, or substitute with other commands to achieve the same goal outside tmux.
When unsure whether a command will be long-running (large directories, bulk file ops, network transfers): default to tmux.

  **Waiting for tmux commands to finish:**
  Use `~/.claude/scripts/tmux-exec.sh <session> <command>` to send a command and wait for completion.
  It blocks until done and returns the pane output. NEVER use `sleep N && tmux capture-pane` — it is blocked by a hook.
  Example: `~/.claude/scripts/tmux-exec.sh claude-running-myproject "python train.py --epochs 5"`

### Manual Trigger (user-initiated, interactive REPL)

If the pane shows a REPL prompt (`In [N]:`, `(Pdb)`, `ipdb>`, `>>>`) AND the user has asked you to cooperate in it: do NOT use `tmux-exec.sh` (its wait-for payload hangs in a REPL). Use `~/.claude/scripts/tmux-capture.sh <session> [lines]` to read, and plain `tmux send-keys` to send. Ask before sending keys only when they would change global state irreversibly (`rm`, file overwrites, `pip install`, `del`, connection-closing, remote writes) — reversible introspection does not need asking. SSH is NOT a REPL for this rule.

## Debugging Discipline

When debugging, modify the failing script in place — don't create a new test script. Comment out, tweak, or add minimal instrumentation to the existing code so you can isolate the smallest change that triggers the error. This keeps the debugging context grounded in the real code path.

## Failure Protocol

- Default to short waits (1-2s) when checking command output. Only increase for genuinely long-running tasks.
- NEVER blindly retry or guess. When something fails, stop and discuss root cause with the user.
- Three failures on the same problem: STOP. Rethink from first principles and discuss with the user before trying again.

## Scale-Up Discipline

For time-consuming or hard-to-reverse tasks (training, data pipelines, deployments, migrations): always start at the smallest viable scale first. Verify correctness, then scale up. NEVER jump to full scale.

## Git Safety — Never Overwrite Code You Didn't Change

- Before committing ANY file: run `git diff HEAD -- <file>` and `git log --oneline -3 -- <file>` to verify you know what changed and that no newer version exists.
- NEVER do bulk "sync" or "snapshot" commits that stage files you didn't modify in this session. The user or another Claude session may have made changes you don't know about.
- NEVER assume your context's version of a file is the latest. Always read from disk before editing. Always check git history before committing.
- If you see uncommitted changes in a file you didn't touch, DO NOT stage it. Ask the user first.

## Tool Preferences

- Prefer dedicated tools (Read, Grep, Glob, Edit) over shell aliases when available.
- Provide no more than three alternative approaches.
- When modifying code, make the minimal necessary edits.
- Suggest at most two verification checks per response.
