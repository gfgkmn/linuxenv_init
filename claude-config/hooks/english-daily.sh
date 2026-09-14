#!/usr/bin/env bash
# SessionStart. Many sessions run at once, so a shared day-stamp keeps this to
# the first one of the day — the drill has to sit inside real work, but it stops
# being practice the moment it becomes wallpaper.
set -u
STATE="${ENGLISH_LAB_HOME:-$HOME/.claude/english}"
STAMP="$STATE/.shown-today"
TODAY="$(date +%F)"
[ -d "$STATE" ] || exit 0
[ "$(cat "$STAMP" 2>/dev/null)" = "$TODAY" ] && exit 0
OUT="$("$HOME/.claude/skills/english-lab/english.py" drill --brief 2>/dev/null)" || exit 0
[ -z "$OUT" ] && exit 0
echo "$TODAY" > "$STAMP"
printf '%s\n' "$OUT"
