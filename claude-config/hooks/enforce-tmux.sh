#!/bin/bash
# .claude/hooks/enforce-tmux.sh
# PreToolUse hook: rejects long-running commands not routed through tmux.
# Also rejects pipe-to-tee in tmux commands (blocks Ctrl+C).
# Claude Code passes hook input as JSON via stdin.

set -euo pipefail

# ── Response helpers ──
allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}
deny() {
  local reason="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check Bash tool calls
if [ "$TOOL" != "Bash" ]; then
  allow
fi

COMMAND_TRIMMED=$(echo "$COMMAND" | sed 's/^[[:space:]]*//')

# ── Rule: Block sleep+capture-pane pattern (use tmux-exec.sh instead) ──
if echo "$COMMAND" | grep -qE 'sleep\s+[0-9]+.*tmux\s+capture-pane'; then
  deny "Do NOT use sleep+capture-pane to poll tmux. Use: bash ~/.claude/scripts/tmux-exec.sh <session> <command> — it waits for completion instantly via tmux wait-for."
fi

# ── Rule: Block pipe-to-tee inside tmux send-keys ──
# `| tee` in tmux blocks Ctrl+C signal propagation.
if echo "$COMMAND" | grep -q "tmux" && echo "$COMMAND" | grep -qE '\|\s*tee\b'; then
  deny "Do NOT use | tee inside tmux — it blocks Ctrl+C. Redirect to a log file instead (e.g., command > log.txt 2>&1) or rely on the programs own logging."
fi

# ── Known-short: always approve immediately ──
# Python one-liners, module queries, version checks, etc.
PYTHON_SHORT_PATTERNS=(
  "^python[3]? -c "
  "^python[3]? -m json\."
  "^python[3]? -m pip"
  "^python[3]? --version"
  "^python[3]? -V"
  "^python[3]? -m py_compile"
  "^python[3]? -m site"
  "^python[3]? -m this"
  "^python[3]? -m compileall"
  "^python[3]? setup.py"
)

for pattern in "${PYTHON_SHORT_PATTERNS[@]}"; do
  if echo "$COMMAND_TRIMMED" | grep -qE "$pattern"; then
    allow
  fi
done

# ── Known-long patterns by binary ──
# These are always long-running regardless of arguments.
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

for pattern in "${ALWAYS_LONG_BINARIES[@]}"; do
  if echo "$COMMAND_TRIMMED" | grep -qE "$pattern"; then
    if echo "$COMMAND" | grep -q "tmux"; then
      allow
    fi
    deny "Long-running command. Run in tmux: bash ~/.claude/scripts/tmux-exec.sh claude-running-\$(basename \$PWD) '$COMMAND_TRIMMED'"
  fi
done

# ── Python script heuristic: check script name and arguments ──
if echo "$COMMAND_TRIMMED" | grep -qE "^python[3]? "; then
  # Extract the script name / first argument
  SCRIPT_ARG=$(echo "$COMMAND_TRIMMED" | sed -E 's/^python[3]? +//' | awk '{print $1}')

  # Known long-running script name patterns
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
  )

  for pattern in "${LONG_SCRIPT_PATTERNS[@]}"; do
    if echo "$SCRIPT_ARG" | grep -qiE "$pattern"; then
      if echo "$COMMAND" | grep -q "tmux"; then
        allow
      fi
      deny "'$SCRIPT_ARG' looks long-running. Run in tmux: bash ~/.claude/scripts/tmux-exec.sh claude-running-\$(basename \$PWD) '$COMMAND_TRIMMED'"
    fi
  done

  # Known long-running argument patterns (epochs, serve flags, etc.)
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

  for pattern in "${LONG_ARG_PATTERNS[@]}"; do
    if echo "$COMMAND_TRIMMED" | grep -qiE "$pattern"; then
      if echo "$COMMAND" | grep -q "tmux"; then
        allow
      fi
      deny "Arguments suggest long-running task ($pattern). Run in tmux: bash ~/.claude/scripts/tmux-exec.sh claude-running-\$(basename \$PWD) '$COMMAND_TRIMMED'"
    fi
  done
fi

# ── Non-Python known-long commands ──
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

for pattern in "${OTHER_LONG_PATTERNS[@]}"; do
  if echo "$COMMAND_TRIMMED" | grep -qE "$pattern"; then
    if echo "$COMMAND" | grep -q "tmux"; then
      allow
    fi
    deny "This looks long-running. Run in tmux: bash ~/.claude/scripts/tmux-exec.sh claude-running-\$(basename \$PWD) '$COMMAND_TRIMMED'"
  fi
done

# ── Default: approve ──
allow
