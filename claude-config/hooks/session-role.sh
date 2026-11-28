#!/bin/bash
# SessionStart hook: give a main session the rule file for its role.
#
# The role is $AGENT_ROLE if set, else the session's agent name
# (`claude --agent <name>`), else "solo". agent-rules/roles.map lists the files
# for each role; a name that is not listed means solo.
#
# CLAUDE.md loads what every role shares. This hook adds the one part that
# differs, so a session reads its own role and nothing about the others.
# It only adds context. It decides nothing and blocks nothing.

set -uo pipefail

# The rules sit beside this script's real directory (hooks/ and agent-rules/
# are siblings in claude-config), so no ~/.claude/agent-rules link is needed.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RULES="${AGENT_RULES_DIR:-$HERE/../agent-rules}"
[ -d "$RULES" ] || RULES="$HOME/.claude/agent-rules"
MAP="$RULES/roles.map"
LIMIT=9500   # Claude Code caps a hook's additionalContext at 10,000 characters

INPUT=$(cat)
if [ ! -r "$MAP" ]; then
  echo "session-role.sh: no roles.map under $RULES; no role file added" >&2
  exit 0
fi

files_for() {
  awk -v r="$1" '{ sub(/#.*/, "") } $1 == r { $1 = ""; print; exit }' "$MAP"
}

ROLE="${AGENT_ROLE:-}"
[ -n "$ROLE" ] || ROLE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
FILES=""
[ -n "$ROLE" ] && FILES=$(files_for "$ROLE")
if [ -z "${FILES// /}" ]; then
  ROLE="solo"
  FILES=$(files_for solo)
fi
[ -n "${FILES// /}" ] || exit 0

TEXT=""
for f in $FILES; do
  [ -r "$RULES/$f" ] || continue
  # Drop HTML comments: they are notes for gfgkmn, not rules.
  PART=$(perl -0pe 's/<!--.*?-->\n?//gs' "$RULES/$f")
  TEXT="$TEXT$PART"$'\n\n'
done
[ -n "$TEXT" ] || exit 0

if [ "${#TEXT}" -gt "$LIMIT" ]; then
  echo "session-role.sh: rules for role $ROLE are ${#TEXT} characters, over the $LIMIT limit; nothing injected" >&2
  exit 0
fi

jq -cn --arg text "$TEXT" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $text}}'
exit 0
