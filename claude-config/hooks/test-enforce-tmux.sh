#!/bin/bash
# Regression cases for enforce-tmux.sh.
# Usage: bash test-enforce-tmux.sh [path/to/enforce-tmux.sh]
# Feeds each command to the hook as Claude Code would, and compares the
# decision with the expected one. Exits non-zero if any case fails.

HOOK="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/enforce-tmux.sh}"
PASS=0
FAIL=0

check() {
  local expect="$1" cmd="$2" out got
  out=$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$HOOK" 2>&1)
  if [ -z "$out" ]; then
    # No output = no decision: the normal permission flow decides. A hook
    # that answers "allow" here would skip that flow, so "allow" must fail.
    got="pass"
  else
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
    [ -n "$got" ] || got="INVALID-JSON"
  fi
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  expected %-5s got %-12s  %s\n' "$expect" "$got" "$cmd"
  fi
}

# ── Long-running, bare ──
check deny  'python train.py --epochs 5'
check deny  'pytest tests/'
check deny  'make all'
check deny  'torchrun --nproc_per_node 4 main.py'

# ── Long-running, behind something else ──
check deny  'cd /proj && python train.py --epochs 5'
check deny  "cd 'app' && python train.py"
check deny  'CUDA_VISIBLE_DEVICES=0 python train.py --epochs 5'
check deny  'CUDA_VISIBLE_DEVICES=0,1 WANDB_MODE="offline" python train.py'
check deny  'source .venv/bin/activate && python finetune.py'
check deny  'time python train.py'
check deny  'nohup python train.py &'
check deny  'env FOO=1 python train.py'
check deny  '/opt/homebrew/bin/python3 train.py'
check deny  'python3.11 train.py'
check deny  'python -u train.py'
check deny  'python -m scripts.train --lr 1e-4'
check deny  'python -m pytest tests/'
check deny  'uv run python train.py'
check deny  'conda run -n ml python train.py'
check deny  'bash -c "cd x && python train.py"'
check deny  'bash scripts/train.sh'
check deny  './run_training.sh --gpus 2'
check deny  'python train.py --name "run 1"'
check deny  'echo start; make all'
check deny  'echo tmux && python train.py'
check deny  'python -c "print(1)" && python train.py --epochs 100'
check deny  $'cd /proj\npython train.py'
check deny  'for s in 1 2; do python train.py --seed $s; done'
check deny  'ls | wc -l; (cd sub && python evaluate.py)'
check deny  'echo $(python generate.py)'

# ── Short or already in tmux: the hook must stay silent ──
check pass  'ls -la'
check pass  'git status'
check pass  'python -c "print(1)"'
check pass  'python -m pip list'
check pass  'python --version'
check pass  'cat train.py'
check pass  'grep -rn "pytest" .'
check pass  'git commit -m "fix; python train.py now works"'
check pass  'echo "make all && python train.py"'
check pass  "echo 'cd x; python train.py'"
check pass  $'python - <<\'EOF\'\nimport sys; print(sys.version)\nmake = 1; train = 2\nEOF'
check pass  'bash install.sh'
check pass  'bash ~/.claude/hooks/test-enforce-tmux.sh'
check pass  '~/.claude/scripts/tmux-exec.sh claude-running-x "python train.py --epochs 5"'
check pass  "tmux send-keys -t claude-running-x 'python train.py --epochs 5' Enter"
check pass  "tmux send-keys -t claude-running-x 'cd /proj' Enter && tmux send-keys -t claude-running-x 'make all' Enter"
check pass  'tmux capture-pane -t claude-running-x -p'

# ── Existing tmux rules ──
check deny  'sleep 5 && tmux capture-pane -t x -p'
check deny  "tmux send-keys -t x 'python train.py | tee log.txt' Enter"

# ── enforce-shot.sh: same rule, it objects or stays silent ──
TMUX_HOOK="$HOOK"
HOOK="$(dirname "$TMUX_HOOK")/enforce-shot.sh"
check pass   'ls -la'
check pass   '~/.claude/scripts/cc-shot.sh window Emacs'
check pass   'xcrun simctl io booted screenshot /tmp/s.png'
check deny   'screencapture -x /tmp/s.png'
check deny   'cd /tmp && screencapture -x s.png'
HOOK="$TMUX_HOOK"

# ── No shell hook here may answer allow or defer ──
# "allow" skips the permission prompt for the call; "defer" parks the call in
# subagents and `claude -p` runs, so it never happens. A hook with no objection
# prints nothing. (audit_edit.py answers allow only after gfgkmn approves.)
DECIDERS=$(grep -lE 'permissionDecision"?[: ]+"(allow|defer)"' "$(dirname "$HOOK")"/*.sh 2>/dev/null \
  | grep -v "$(basename "${BASH_SOURCE[0]}")" || true)
if [ -n "$DECIDERS" ]; then
  FAIL=$((FAIL + 1))
  printf 'FAIL  these hooks answer allow or defer: %s\n' "$(echo $DECIDERS)"
else
  PASS=$((PASS + 1))
fi

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" = 0 ]
