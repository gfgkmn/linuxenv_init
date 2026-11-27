#!/bin/bash
# SubagentStart hook: give a subagent the rule files listed for it in
# agent-rules/subagents.map.
#
# Subagent definitions set `omitClaudeMd: true`, so they no longer load the
# lead's rules. This hook supplies the kernel (and a seat, where listed) so the
# split is enforced by Claude Code and does not depend on the brief.
#
# Prints nothing for a subagent that is not in the map.

set -uo pipefail

RULES="${AGENT_RULES_DIR:-$HOME/.claude/agent-rules}"
MAP="$RULES/subagents.map"
LIMIT=9500   # Claude Code caps a hook's additionalContext at 10,000 characters

INPUT=$(cat)
TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
[ -n "$TYPE" ] && [ -r "$MAP" ] || exit 0

FILES=$(awk -v t="$TYPE" '$1 == t { $1 = ""; print; exit }' "$MAP")
[ -n "$FILES" ] || exit 0

TEXT=""
for f in $FILES; do
  [ -r "$RULES/$f" ] || continue
  # Drop HTML comments: they are notes for gfgkmn, not rules.
  PART=$(perl -0pe 's/<!--.*?-->\n?//gs' "$RULES/$f")
  TEXT="$TEXT$PART"$'\n\n'
done
[ -n "$TEXT" ] || exit 0

if [ "${#TEXT}" -gt "$LIMIT" ]; then
  echo "subagent-rules.sh: rules for $TYPE are ${#TEXT} characters, over the $LIMIT limit; nothing injected" >&2
  exit 0
fi

jq -cn --arg text "$TEXT" \
  '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $text}}'
exit 0
