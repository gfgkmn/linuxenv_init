#!/usr/bin/env bash
# Claude Code statusLine command.
#
# Two responsibilities:
#   1. Render a two-line status: git/venv/cwd/date on top, ctx%/cost/audit-mode/prompt below.
#   2. Export a tiny per-session state JSON to ~/.claude/cc-state/<session_id>.json
#      so claude-code-bridge's Emacs dashboard can show live context window %,
#      cost, model, and rate-limit state without depending on iTerm's
#      content-capture heuristic (which goes blind during scrollback).
#
# Invoked by CC via:
#   "statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}
#
# Deployed to every host via linuxenv_init sync; same file powers local + remote.

set -o pipefail

input=$(cat)

# ── Extract fields we need ───────────────────────────────────────────────
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
session_id=$(echo "$input" | jq -r '.session_id // empty')
current_date=$(date "+%m/%d/%y")
current_time=$(date "+%H:%M:%S")

# ── Git info (branch + upstream divergence + dirty marker) ──────────────
git_info=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        git_info="{$branch"
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
        if [ -n "$upstream" ]; then
            ahead=$(git -C "$cwd" rev-list --count "@{upstream}..HEAD" 2>/dev/null)
            behind=$(git -C "$cwd" rev-list --count "HEAD..@{upstream}" 2>/dev/null)
            if [ "${ahead:-0}" -gt 0 ] && [ "${behind:-0}" -gt 0 ]; then
                git_info+="↕"
            elif [ "${ahead:-0}" -gt 0 ]; then
                git_info+="↑"
            elif [ "${behind:-0}" -gt 0 ]; then
                git_info+="↓"
            fi
        fi
        if ! git -C "$cwd" diff --quiet 2>/dev/null \
           || ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
            git_info+="⚡️"
        fi
        git_info+="}"
    fi
fi

# ── Conda / venv badge ──────────────────────────────────────────────────
conda_info=""
if [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
    conda_info="\033[1;33m(${CONDA_DEFAULT_ENV})\033[0m "
elif [ -n "${VIRTUAL_ENV:-}" ]; then
    venv_name=$(basename "$VIRTUAL_ENV")
    conda_info="\033[1;33m(${venv_name})\033[0m "
fi

# ── Context-window bar ──────────────────────────────────────────────────
make_bar() {
    local pct=$1
    local filled=$((pct / 12))
    local remainder=$((pct % 12))
    if [ $remainder -gt 6 ]; then filled=$((filled + 1)); fi
    if [ $filled -gt 8 ]; then filled=8; fi
    local empty=$((8 - filled))
    local color="32"
    if [ $pct -gt 75 ]; then color="31"
    elif [ $pct -gt 50 ]; then color="33"
    fi
    local bar=""
    bar+="\033[1;${color}m"
    if [ $filled -gt 0 ]; then for _ in $(seq 1 $filled); do bar+="▰"; done; fi
    bar+="\033[0;2m"
    if [ $empty -gt 0 ]; then for _ in $(seq 1 $empty); do bar+="▱"; done; fi
    bar+="\033[0m"
    printf "%b" "$bar"
}
ctx_bar=$(make_bar "$ctx_pct")
if   [ "$ctx_pct" -gt 75 ]; then ctx_color="31"
elif [ "$ctx_pct" -gt 50 ]; then ctx_color="33"
else ctx_color="32"
fi

# ── Audit-mode badge (~/.claude/.audit-mode per project) ────────────────
audit_mode="permissive"
audit_file="$cwd/.claude/.audit-mode"
if [ -f "$audit_file" ]; then
    audit_mode=$(tr -d '\n' < "$audit_file" 2>/dev/null)
fi
case "$audit_mode" in
    audit)      audit_badge="\033[1;33m[audit]\033[0m" ;;
    strict)     audit_badge="\033[1;31m[strict]\033[0m" ;;
    *)          audit_badge="\033[1;32m[permissive]\033[0m" ;;
esac

# ── Render two lines ────────────────────────────────────────────────────
printf "\033[1;34m[claude]:\033[0m \033[1;32m%s\033[0m %b\033[1;36m%s\t\033[1;35m%s %s\033[0m\n" \
    "$git_info" "$conda_info" "$cwd" "$current_date" "$current_time"

printf "  💰\$%.4f \033[1;${ctx_color}mctx:%d%%\033[0m %b %b \033[1;34m❯\033[0m" \
    "$cost" "$ctx_pct" "$ctx_bar" "$audit_badge"

# ── State export for claude-code-bridge dashboard ───────────────────────
# Writes ~/.claude/cc-state/<session_id>.json on every tick. Per-UUID files
# are atomic to overwrite, safe across concurrent CC instances, and cheap
# to read from Emacs (direct cat / TRAMP cat). `|| true' keeps the
# statusline output robust against jq / filesystem hiccups.
if [ -n "$session_id" ]; then
    state_dir="$HOME/.claude/cc-state"
    mkdir -p "$state_dir" 2>/dev/null
    {
        echo "$input" | jq -c --arg t "$(date +%s)" '{
            session_id,
            session_name: (.session_name // null),
            cwd: .workspace.current_dir,
            project_dir: .workspace.project_dir,
            model: .model.display_name,
            cost_usd: .cost.total_cost_usd,
            ctx_used_pct: .context_window.used_percentage,
            ctx_in: .context_window.total_input_tokens,
            ctx_out: .context_window.total_output_tokens,
            ctx_size: .context_window.context_window_size,
            exceeds_200k: .exceeds_200k_tokens,
            rate_5h: (.rate_limits.five_hour.used_percentage // null),
            rate_7d: (.rate_limits.seven_day.used_percentage // null),
            updated_at: ($t | tonumber)
        }' > "$state_dir/$session_id.json"
    } 2>/dev/null || true
fi
