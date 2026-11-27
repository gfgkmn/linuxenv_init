#!/usr/bin/env bash
# cc-bridge-hook.test.sh -- the `permreq' wait of cc-bridge-hook.sh, with no
# Emacs and no Claude Code: a stand-in `emacsclient' says what the probe
# should hear and notes the directory the hook waits in; the test then
# writes the answer there, as Emacs would.
#
# Usage: bash cc-bridge-hook.test.sh        (exit 1 when a check fails)
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$here/cc-bridge-hook.sh"
work="$(mktemp -d -t cc-bridge-hook-test.XXXXXX)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home/.claude"

# The stand-in: `--eval EXPR' prints $FAKE_PROBE; `--no-wait --eval EXPR'
# appends EXPR to $work/calls.
/bin/cat > "$work/bin/emacsclient" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = "--no-wait" ]; then echo "\$3" >> "$work/calls"; exit 0; fi
echo "\${FAKE_PROBE:-nil}"
FAKE
chmod +x "$work/bin/emacsclient"

payload='{"session_id":"11111111-2222","cwd":"/w","hook_event_name":"PermissionRequest","tool_name":"WebFetch","tool_input":{"url":"https://example.com"},"permission_suggestions":[{"type":"addRules","destination":"localSettings","rules":[{"toolName":"WebFetch","ruleContent":"domain:example.com"}],"behavior":"allow"}]}'

failed=0
check() {   # check <label> <got> <want>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s\n        got:  %s\n        want: %s\n' "$1" "$2" "$3"; failed=1; fi
}

# run <probe> <answer|-none-> [seconds] -> stdout of the hook in $out,
# what was left of its directory in $left, how long it took in $took.
run() {
  local probe="$1" answer="$2" budget="${3:-20}" dir start
  : > "$work/calls"; : > "$work/out"
  start=$SECONDS
  ( printf '%s' "$payload" \
      | env -u SSH_CONNECTION HOME="$work/home" PATH="$work/bin:$PATH" \
            FAKE_PROBE="$probe" CC_BRIDGE_HOLD_SECONDS="$budget" \
            bash "$hook" permreq > "$work/out" ) &
  local pid=$!
  dir=""
  for _ in $(seq 1 50); do
    dir="$(sed -n 's/.* "\([^"]*cc-bridge-hold[^"]*\)")$/\1/p' "$work/calls" | tail -n1)"
    [ -n "$dir" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  held="$dir"
  if [ -n "$dir" ] && [ "$answer" != "-none-" ]; then
    pidfile="$(/bin/cat "$dir/pid" 2>/dev/null)"
    printf '%s' "$answer" > "$dir/answer.part" && mv "$dir/answer.part" "$dir/answer"
  fi
  wait "$pid"
  took=$((SECONDS - start))
  out="$(/bin/cat "$work/out")"
  left="gone"; [ -n "$dir" ] && [ -e "$dir" ] && left="still there"
}

echo "an Emacs that can answer"
run hold allow
check "allow is printed as CC's decision" "$out" \
  '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
check "the hook waited in a directory of its own" "$([ -n "$held" ] && echo yes)" yes
check "and removed it" "$left" gone
check "Emacs was told through the entry that takes the directory" \
  "$(grep -c 'claude-code-bridge--on-permission-hold-from-file' "$work/calls")" 1

run hold allow-always
check "allow-always carries the rule CC suggested" "$out" \
  '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"addRules","destination":"localSettings","rules":[{"toolName":"WebFetch","ruleContent":"domain:example.com"}],"behavior":"allow"}]}}}'

run hold deny
check "deny stops the turn" "$out" \
  '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"The user declined this from Emacs.","interrupt":true}}}'

run hold ""
check "an empty answer prints nothing" "$out" ""
check "and ends the hook at once" "$([ "$took" -le 3 ] && echo yes)" yes

run hold "something-else"
check "a word the hook does not know prints nothing" "$out" ""

run hold -none- 2
check "no answer in time prints nothing" "$out" ""
check "and the hook gave up at its limit" "$([ "$took" -ge 2 ] && [ "$took" -le 5 ] && echo yes)" yes
check "its directory is removed" "$left" gone

echo "an Emacs that only knows the old entry"
run t -none- 20
check "the hook does not wait" "$([ "$took" -le 3 ] && echo yes)" yes
check "prints nothing" "$out" ""
check "and tells Emacs as before" \
  "$(grep -c 'claude-code-bridge--on-permission-request-from-file' "$work/calls")" 1

echo "no bridge in Emacs"
run nil -none- 20
check "the hook does not wait" "$([ "$took" -le 3 ] && echo yes)" yes
check "and tells nobody" "$(wc -l < "$work/calls" | tr -d ' ')" 0

[ "$failed" -eq 0 ] && echo "ALL PASS" || echo "FAILED"
exit "$failed"
