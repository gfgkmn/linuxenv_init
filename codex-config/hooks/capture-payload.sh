#!/usr/bin/env bash
# capture-payload.sh — observe a Codex hook event, decide nothing.
#
# Codex's hook payloads are documented nowhere we can read, so the first
# job of the Codex wiring is to record real ones: field names differ from
# Claude Code's (no `last_assistant_message', a `turn_id' instead of
# `prompt_id', tool names `exec'/`apply_patch' instead of `Bash'/`Edit').
# Everything downstream — the enforcement hooks, the Emacs bridge — is
# written against what lands here.
#
# Contract: read stdin, write one file, print NOTHING (stdout is parsed as
# the hook's JSON decision), always exit 0.  It must be impossible for this
# to block or fail a turn.
#
# Usage in hooks.json:  bash '<path>/capture-payload.sh' <EventName>

ev="${1:-unknown}"
dir="${CODEX_HOOK_PAYLOAD_DIR:-$HOME/.codex/hook-payloads}"

mkdir -p "$dir" 2>/dev/null || exit 0
f="$dir/$(date -u +%Y%m%dT%H%M%S)-$$-${ev}.json"
cat > "$f" 2>/dev/null

# Bounded: keep the newest 200, drop the rest.  A chatty session must not
# fill the disk just because nobody came back to read these.
ls -t "$dir"/*.json 2>/dev/null | tail -n +201 | while IFS= read -r old; do
  rm -f "$old" 2>/dev/null
done

exit 0
