#!/bin/bash
# PreToolUse hook (matcher: Bash|Write): before a plugin or skill is added,
# put the three questions in front of gfgkmn.
#
# Fires when the agent is about to
#   - install or enable a plugin, add a marketplace, or add a skill by CLI;
#   - write a SKILL.md that does not exist yet.
# It answers "ask": Claude Code shows a permission prompt with the questions,
# and gfgkmn decides. For everything else it prints nothing, so it never
# approves or blocks a call on its own.
#
# Not covered: installs gfgkmn makes by hand in the /plugin menu or on
# claude.ai. Those never pass through a tool call.

set -uo pipefail

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

ask() {
  jq -cn --arg what "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: (
    "Skill gate — " + $what + "\n" +
    "1. Has the agent done this task without it, and where did the result fall short?\n" +
    "2. Is the missing piece yours (then write it yourself), or machinery and fast-changing provider knowledge (then install)?\n" +
    "3. What does it add to every session? After installing: claude plugin details <name>")}}'
  exit 0
}

case "$TOOL" in
  Bash)
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SPLITTER="$HOOK_DIR/split_command.py"
    [ -f "$SPLITTER" ] || SPLITTER="$HOME/.claude/hooks/split_command.py"
    PY=$(command -v python || command -v python3 || true)
    SEGMENTS=""
    if [ -n "$PY" ] && [ -f "$SPLITTER" ]; then
      SEGMENTS=$(printf '%s' "$COMMAND" | "$PY" "$SPLITTER" 2>/dev/null || true)
    fi
    [ -n "$SEGMENTS" ] || SEGMENTS="$COMMAND"
    re='^(claude plugins? (install|i|enable) |claude plugins? marketplace add |hf skills add|(npx|bunx) skills add )'
    while IFS= read -r SEG; do
      if [[ "$SEG " =~ $re ]]; then
        ask "about to add: $SEG"
      fi
    done <<< "$SEGMENTS"
    ;;
  Write)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    re='/skills/[^/]+/SKILL\.md$'
    if [[ "$FILE" =~ $re ]] && [ ! -e "$FILE" ]; then
      ask "about to write a new skill: $FILE"
    fi
    ;;
esac
exit 0
