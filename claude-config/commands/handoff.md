---
description: Generate or load a handoff document for AI agent context transfer. Use "/handoff" to generate before compact, "/handoff load" to resume from a previous handoff.
argument-hint: [load]
---

# Handoff Document Generator

Two modes based on `$ARGUMENTS`:

## Mode: Load (`/handoff load`)

If `$ARGUMENTS` contains "load":

1. Find the most recent handoff file:
```bash
ls -t ./claude-handoff/*-handoff*.md 2>/dev/null | head -1
```

2. If no file found, tell the user: "No handoff files found in ./claude-handoff/. Nothing to load."

3. If found, read the file and then:
   - Summarize the handoff to the user in 3-5 lines (task, progress, next step)
   - State: "I've loaded the handoff context. Ready to continue — what should I focus on?"
   - Treat the handoff content as authoritative context for this session. Follow the "First Step for Next Agent" unless the user directs otherwise.

**Stop here for load mode. Do not execute the generation steps below.**

---

## Mode: Generate (default, no arguments or additional context in `$ARGUMENTS`)

Generate a structured handoff summary so the next AI agent can continue work without access to this conversation's full context.

## Step 1: Detect Project Type

Run these checks to determine if this is an ML/training project:

```bash
# Check for ML signals in the project
ml_signals=0

# Python ML imports
grep -rl "import torch\|import verl\|import transformers\|from accelerate\|import deepspeed\|import ray" --include="*.py" . 2>/dev/null | head -3 && ml_signals=$((ml_signals+1))

# Training configs
ls -1 *.yaml *.yml configs/*.yaml configs/*.yml 2>/dev/null | head -3 && ml_signals=$((ml_signals+1))

# Checkpoint artifacts
find . -maxdepth 3 \( -name "checkpoint-*" -o -name "*.pt" -o -name "*.safetensors" -o -name "*.ckpt" \) 2>/dev/null | head -5 && ml_signals=$((ml_signals+1))

echo "ML_SIGNALS=$ml_signals"
```

If `ML_SIGNALS >= 1`, this is an **ML project** — use the ML-enhanced template. Otherwise use the general template.

## Step 2: Auto-Capture Runtime State

Run all of these and collect the output. Do NOT show raw output to user — synthesize it into the handoff doc.

### Always capture:

```bash
# Git state
git rev-parse --abbrev-ref HEAD 2>/dev/null
git log --oneline -5 2>/dev/null
git status --short 2>/dev/null
```

```bash
# Active tmux sessions related to this project
tmux list-sessions 2>/dev/null | grep claude-running || echo "No active tmux sessions"
```

### If tmux session exists, capture pane output:

```bash
# Last 80 lines from the active tmux pane
for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep claude-running); do
  echo "=== Session: $s ==="
  tmux capture-pane -t "$s" -p -S -80 2>/dev/null
done
```

### ML-only captures (skip for general projects):

```bash
# GPU state
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null || echo "No GPU / nvidia-smi not available"
```

```bash
# Find checkpoints and their timestamps
find . -maxdepth 4 \( -name "checkpoint-*" -o -name "*.pt" -o -name "*.safetensors" \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -10 | awk '{print strftime("%Y-%m-%d %H:%M", $1), $2}' || \
find . -maxdepth 4 \( -name "checkpoint-*" -o -name "*.pt" -o -name "*.safetensors" \) -exec stat -f '%Sm %N' -t '%Y-%m-%d %H:%M' {} \; 2>/dev/null | sort -r | head -10
```

```bash
# Find training logs
find . -maxdepth 3 \( -name "*.log" -o -name "events.out.tfevents.*" -o -name "trainer_state.json" \) 2>/dev/null | head -10
```

```bash
# Conda/venv environment
conda info --envs 2>/dev/null | grep '*' || echo "VIRTUAL_ENV=$VIRTUAL_ENV"
```

## Step 3: Synthesize and Write

Review the full conversation context. Combine it with the auto-captured state above. Write the handoff document.

### Output path

```
./claude-handoff/{yymmdd}-handoff.md
```

Where `{yymmdd}` is today's date (e.g., `260409`). Create the `claude-handoff/` directory at the **git repo root** if it doesn't exist.

If a file with the same name already exists, append a sequential suffix: `260409-handoff-2.md`, `260409-handoff-3.md`.

### General Template

```markdown
# Handoff — {date} — {one-line task summary}

## 1. Task Objective
What problem we're solving, expected output, and completion criteria.

## 2. Current Progress
What has been completed: analysis, modifications, discussions, outputs.
Be specific — name files changed, commands run, decisions made.

## 3. Key Context
- Important background the next agent won't have
- User's explicit requirements
- Known constraints
- Key decisions already made and their rationale
- Important assumptions

## 4. Key Findings
Most important conclusions, patterns, anomalies, root causes, or design judgments.

## 5. Unfinished Items
Ordered by priority. Each item should be actionable.

## 6. Suggested Handoff Path
- Which files/modules/logs to read first
- What to verify before making changes
- Recommended next action

## 7. Risks & Caveats
- What's easy to misjudge
- Directions already tried and abandoned (and why)
- Potential traps

## First Step for Next Agent
One concrete, actionable instruction to start with.
```

### ML-Enhanced Template

Use the general template above, PLUS insert these sections after "Key Findings":

```markdown
## 5. Experiment Log
| # | Config / Params | Command | Result / Metrics | Notes |
|---|----------------|---------|-----------------|-------|
| 1 | ... | ... | ... | ... |

Summarize from conversation context: what was tried, what config, what outcome.

## 6. Active Resources
- **Git branch:** {branch}
- **Tmux session:** {session name and what's running}
- **GPU state:** {GPU utilization, memory}
- **Conda/venv:** {active environment}
- **Latest checkpoints:** {paths with timestamps}
- **Training logs:** {paths}
- **Running processes:** {if any visible in tmux}

## 7. Reproduction Commands
Exact commands to resume or replicate the current state:
```bash
# Activate environment
...
# Resume training / run eval
...
```

## 8. Metrics Snapshot
Last known training/eval numbers. Include step/epoch if available.
- Training loss: ...
- Eval metric: ...
- Reward (if RL): ...
```

Then continue with the remaining general sections (Unfinished Items, Handoff Path, Risks, First Step), renumbered accordingly.

## Rules

- **Synthesize, don't dump.** Raw tmux output and command results go into the appropriate sections, not as appendices.
- **Be specific.** Use file paths, class names, config keys, metric values, command strings. Avoid vague language.
- **This is agent-to-agent.** No pleasantries, no user-facing polish. Optimize for the next agent's cold start.
- **Conversation context is primary.** The auto-captured state supplements it — task objectives, decisions, and reasoning come from the conversation.
- **If information is unavailable, say so.** Don't fabricate metrics or guess at decisions. Write "Unknown — verify by ..." instead.
- If `$ARGUMENTS` is provided, treat it as additional context or instructions for the handoff (e.g., "focus on the data pipeline issue").
