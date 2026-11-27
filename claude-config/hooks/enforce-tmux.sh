#!/bin/bash
# .claude/hooks/enforce-tmux.sh
# PreToolUse hook: rejects long-running commands not routed through tmux.
# Also rejects pipe-to-tee in tmux commands (blocks Ctrl+C).
# Claude Code passes hook input as JSON via stdin.
#
# The command is first split into the simple commands it would run
# (split_command.py), so `cd x && FOO=1 time python3 train.py` is checked
# the same way as a bare `python train.py`. test-enforce-tmux.sh holds the
# cases this hook must get right.

set -euo pipefail

# ── Response helpers ──
no_objection() {
  # Print nothing. This hook is an extra check, not an approver: with no
  # decision from it, the call goes on through the normal permission flow
  # (allow rules, auto mode's review, or a prompt). Answering "allow" here
  # would skip that flow for every Bash command.
  exit 0
}
deny() {
  # jq builds the JSON, so a reason containing quotes stays valid.
  jq -cn --arg reason "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check Bash tool calls
if [ "$TOOL" != "Bash" ]; then
  no_objection
fi

COMMAND_TRIMMED=$(echo "$COMMAND" | sed 's/^[[:space:]]*//')
TMUX_HINT="Run the original command in tmux: ~/.claude/scripts/tmux-exec.sh claude-running-\$(basename \$PWD) '$COMMAND_TRIMMED'"

# ── Rule: Block sleep+capture-pane pattern (use tmux-exec.sh instead) ──
if echo "$COMMAND" | grep -qE 'sleep\s+[0-9]+.*tmux\s+capture-pane'; then
  deny "Do NOT use sleep+capture-pane to poll tmux. Use: ~/.claude/scripts/tmux-exec.sh <session> <command> — it waits for completion instantly via tmux wait-for."
fi

# ── Rule: Block pipe-to-tee inside tmux send-keys ──
# `| tee` in tmux blocks Ctrl+C signal propagation.
if echo "$COMMAND" | grep -q "tmux" && echo "$COMMAND" | grep -qE '\|\s*tee\b'; then
  deny "Do NOT use | tee inside tmux — it blocks Ctrl+C. To keep a log while the output stays visible, use: tmux pipe-pane -t <session> -o 'cat >> <logfile>'."
fi

# ── Pattern tables ──

# Known-short python invocations: skipped, never long.
PYTHON_SHORT_PATTERNS=(
  "^python -c "
  "^python -m json\."
  "^python -m pip"
  "^python --version"
  "^python -V"
  "^python -m py_compile"
  "^python -m site"
  "^python -m this"
  "^python -m compileall"
  "^python setup.py"
)

# Always long-running regardless of arguments.
ALWAYS_LONG_BINARIES=(
  "^torchrun "
  "^deepspeed "
  "^accelerate launch"
  "^npm run dev"
  "^npm run start"
  "^npm run serve"
  "^npm start"
  "^yarn dev"
  "^yarn start"
  "^pnpm dev"
  "^pnpm start"
  "^cargo run"
  "^cargo build"
  "^go run "
  "^docker compose up"
  "^docker-compose up"
  "^uvicorn "
  "^gunicorn "
  "^flask run"
  "^streamlit run"
  "^jupyter "
  "^tensorboard"
)

# Script names that suggest a long run (python scripts, modules, shell scripts).
LONG_SCRIPT_PATTERNS=(
  "train"
  "finetune"
  "fine_tune"
  "serve"
  "server"
  "benchmark"
  "evaluate"
  "eval"
  "generate"
  "infer"
  "inference"
  "preprocess"
  "download"
  "crawl"
  "scrape"
  "migrate"
  "deploy"
  "main\.py"
  "app\.py"
  "run\.py"
  "launch"
  "worker"
  "daemon"
  "^pytest$"
)

# Python arguments that suggest a long run (epochs, serve flags, etc.)
LONG_ARG_PATTERNS=(
  "--epochs"
  "--num.train"
  "--serve"
  "--host"
  "--port"
  "--workers"
  "--batch.size"
  "--checkpoint"
  "--resume"
  "--data.dir"
  "--output.dir"
)

OTHER_LONG_PATTERNS=(
  "^make "
  "^cmake "
  "^npm test"
  "^npm run build"
  "^pytest"
  "^node .*server"
  "^node .*serve"
  "^node .*app\."
)

matches_any() {
  # matches_any <text> <i|-> <pattern>... ; sets MATCHED to the matched text.
  # One built-in regex match over all patterns: this hook runs on every Bash
  # call, so it must not start a process per pattern.
  local text="$1" nocase="$2" re IFS='|'
  shift 2
  re="$*"
  if [ "$nocase" = i ]; then shopt -s nocasematch; fi
  if [[ "$text" =~ $re ]]; then
    MATCHED="${BASH_REMATCH[0]}"
    shopt -u nocasematch
    return 0
  fi
  shopt -u nocasematch
  return 1
}

# First argument that names what python runs: skips flags, follows `-m`.
python_target() {
  local take_next=0 word
  for word in $1; do
    if [ "$take_next" = 1 ]; then echo "$word"; return; fi
    case "$word" in
      python) ;;
      -m) take_next=1 ;;
      -*) ;;
      *) echo "$word"; return ;;
    esac
  done
}

check_segment() {
  local SEG="$1" TARGET SCRIPT
  local shell_re='^(bash|sh|zsh) ' script_re='^[^ ]+\.sh( |$)'

  if matches_any "$SEG" - "${PYTHON_SHORT_PATTERNS[@]}"; then
    return
  fi

  if matches_any "$SEG" - "${ALWAYS_LONG_BINARIES[@]}"; then
    deny "Long-running command ($SEG). $TMUX_HINT"
  fi

  if [[ "$SEG" == "python "* ]]; then
    TARGET=$(python_target "$SEG")
    if [ -n "$TARGET" ] && matches_any "$TARGET" i "${LONG_SCRIPT_PATTERNS[@]}"; then
      deny "'$TARGET' looks long-running. $TMUX_HINT"
    fi
    if matches_any "$SEG" i "${LONG_ARG_PATTERNS[@]}"; then
      deny "Arguments suggest long-running task ($MATCHED). $TMUX_HINT"
    fi
  fi

  # Shell scripts: `bash scripts/train.sh`, `./train.sh`
  SCRIPT=""
  if [[ "$SEG" =~ $shell_re ]]; then
    for SCRIPT in ${SEG#* }; do
      case "$SCRIPT" in -*) SCRIPT="" ;; *) break ;; esac
    done
  elif [[ "$SEG" =~ $script_re ]]; then
    SCRIPT="${SEG%% *}"
  fi
  if [ -n "$SCRIPT" ] && matches_any "${SCRIPT##*/}" i "${LONG_SCRIPT_PATTERNS[@]}"; then
    deny "'$SCRIPT' looks long-running. $TMUX_HINT"
  fi

  if matches_any "$SEG" - "${OTHER_LONG_PATTERNS[@]}"; then
    deny "This looks long-running ($SEG). $TMUX_HINT"
  fi
}

# ── Split into simple commands, then check each ──
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=$(command -v python || command -v python3 || true)
SEGMENTS=""
if [ -n "$PY" ] && [ -f "$HOOK_DIR/split_command.py" ]; then
  SEGMENTS=$(printf '%s' "$COMMAND" | "$PY" "$HOOK_DIR/split_command.py" 2>/dev/null || true)
fi
# Splitter unavailable: fall back to checking the command as one piece.
[ -n "$SEGMENTS" ] || SEGMENTS="$COMMAND_TRIMMED"

while IFS= read -r SEG; do
  [ -n "$SEG" ] && check_segment "$SEG"
done <<< "$SEGMENTS"

# ── Default: no objection ──
no_objection
