#!/bin/bash
# Claude Code statusLine command
# Mirrors the zsh PROMPT:
#   yellow: hostname  git_info  green: cwd   red: date time
#   cyan: username

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
hostname_s=$(hostname -s)
username=$(whoami)
current_date=$(date "+%y-%m-%d")
current_time=$(date "+%H:%M")

# Git info (mirrors prompt_git_info)
git_info=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        git_info="git:(${branch}"
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
        if [ -n "$upstream" ]; then
            ahead=$(git -C "$cwd" rev-list --count "@{upstream}..HEAD" 2>/dev/null)
            behind=$(git -C "$cwd" rev-list --count "HEAD..@{upstream}" 2>/dev/null)
            if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
                git_info+="↕"
            elif [ "$ahead" -gt 0 ]; then
                git_info+="↑"
            elif [ "$behind" -gt 0 ]; then
                git_info+="↓"
            fi
        fi
        if ! git -C "$cwd" diff --quiet 2>/dev/null || ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
            git_info+="*"
        fi
        git_info+=")"
    fi
fi

# First line: hostname:git_info  cwd   date time
# Second line: username>:
# Colors: yellow=hostname, green=cwd, red=date/time, cyan=username
printf "\033[33m%s:%s\033[0m \033[32m%s\033[0m  \033[31m%s %s\033[0m\n\033[36m%s\033[0m" \
    "$hostname_s" "$git_info" "$cwd" "$current_date" "$current_time" "$username"
