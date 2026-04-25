#!/usr/bin/env bash
# cc-changes-log.sh — append a one-line jsonl record to ./.claude/changes.jsonl
# for every PostToolUse covering Edit / Write / NotebookEdit.
#
# Consumed by `claude-code-review.el' to build a delta-review buffer
# (which files CC touched in this session).  Extracted from the inline
# `bash -c ...' that used to live in settings.json.

set -uo pipefail
input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')
file=$(echo "$input" | jq -r '(.tool_input.file_path // .tool_input.notebook_path // empty)')
ts=$(date +%s)

[ -z "$tool" ] && exit 0
mkdir -p .claude
printf '{"ts":%s,"tool":"%s","file":"%s"}\n' "$ts" "$tool" "$file" >> .claude/changes.jsonl
