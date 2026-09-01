#!/bin/bash
# .claude/hooks/enforce-shot.sh
# PreToolUse hook: screen capture may only happen through scripts/cc-shot.sh.
#
# Rationale: cc-shot.sh resolves the capture rectangle from an allowlisted
# application and never accepts raw coordinates. Denying bare `screencapture`
# (and AppleScript equivalents) here is what makes that allowlist binding
# rather than advisory.
#
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

# Only Bash calls can invoke a capture binary.
if [ "$TOOL" != "Bash" ]; then
  allow
fi

# Anything routed through the sanctioned script is fine — it enforces the
# allowlist itself. Checked first so the rules below never fire on it.
if echo "$COMMAND" | grep -qE '(^|[[:space:]/])cc-shot\.sh([[:space:]]|$)'; then
  allow
fi

# Strip quoted segments before looking for command names, so a word that
# merely appears inside a string — a log predicate, a grep pattern, an echoed
# sentence — cannot trip the rules. Only what survives can be a real command.
UNQUOTED=$(printf '%s' "$COMMAND" | sed -E "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g")

# True when NAME appears in command position: first word of the whole command
# or of any segment after ; | & && || newline, ignoring sudo/command/nohup and
# leading VAR=value assignments. Path prefixes are stripped, so /usr/sbin/foo
# and foo are treated alike.
in_command_position() {
  local name="$1" seg first
  # `<<<` (not a pipe) so the loop runs in this shell and can return early;
  # it also supplies the trailing newline that `read` needs to see the last
  # segment at all.
  while IFS= read -r seg; do
    seg=$(printf '%s' "$seg" \
      | sed -E 's/^[[:space:]]*//
                s/^(sudo|command|nohup|exec)[[:space:]]+//
                s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//')
    first=${seg%%[[:space:]]*}
    first=${first##*/}
    [ "$first" = "$name" ] && return 0
  done <<< "$(printf '%s' "$UNQUOTED" | tr ';|&\n' '\n\n\n\n')"
  return 1
}

# ── Rule: bare screencapture ──
if in_command_position screencapture; then
  deny "Direct screen capture is not allowed. Use: ~/.claude/scripts/cc-shot.sh window <ProcessName> — it captures only apps listed in ~/.claude/shot-allowlist. Run cc-shot.sh list to see them."
fi

# ── Rule: AppleScript screen capture ──
# Command position for osascript, but the capture verb is looked for in the
# original text because the script body normally lives inside quotes.
if in_command_position osascript \
   && printf '%s' "$COMMAND" | grep -qiE 'screen capture|screencapture|capture screen'; then
  deny "AppleScript screen capture bypasses the allowlist. Use: ~/.claude/scripts/cc-shot.sh window <ProcessName>."
fi

# ── Rule: simulator screenshots to an arbitrary device are fine, but keep
# them discoverable by pointing at the wrapper when the whole app is meant. ──
# (simctl can only reach the simulator, so it is allowed unconditionally.)

allow
