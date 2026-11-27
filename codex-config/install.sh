#!/usr/bin/env bash
# install.sh — give Codex the skills, subagents and instructions that
# Claude Code already has, from one source of truth.
#
#   claude-config/skills/*        -> $CODEX_HOME/skills/*          (symlink)
#   codex-config/generated/...    -> $CODEX_HOME/{skills,agents}   (symlink)
#   codex-config/generated/AGENTS.md -> $CODEX_HOME/AGENTS.md      (symlink)
#   codex-config/generated/hooks.json -> $CODEX_HOME/hooks.json    (symlink)
#
# Symlinks, not copies, so editing a SKILL.md once serves both agents.
# Pass --copy if Codex turns out not to follow links.  Idempotent: safe to
# re-run after `python gen.py'.  Anything it would overwrite is moved to
# <file>.bak-<timestamp> first, and a real (non-symlink) directory that
# Codex ships itself is never touched.
#
# Run `python gen.py' first — install.sh only links what is already there.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
CC="$ROOT/claude-config"
GEN="$HERE/generated"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
MODE="symlink"
DRY=""

for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    --dry-run) DRY="1" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
act() { if [ -n "$DRY" ]; then say "  would $*"; else return 1; fi; }

# install SRC DST — link or copy SRC to DST, preserving whatever was there.
install_one() {
  local src="$1" dst="$2" label="$3"
  if [ ! -e "$src" ]; then say "  skip     $label (missing source)"; return; fi

  if [ -L "$dst" ]; then
    local cur; cur="$(readlink "$dst")"
    if [ "$cur" = "$src" ] && [ "$MODE" = symlink ]; then
      say "  ok       $label"; return
    fi
    act "replace link $dst" && return
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    # A real file/dir: either Codex's own, or an earlier --copy install.
    if [ -d "$dst" ] && [ -d "$src" ] && diff -rq "$src" "$dst" >/dev/null 2>&1; then
      say "  ok       $label (identical copy)"; return
    fi
    act "back up $dst" && return
    mv "$dst" "$dst.bak-$STAMP"
    say "  backup   $label -> $(basename "$dst").bak-$STAMP"
  fi

  act "install $label" && return
  mkdir -p "$(dirname "$dst")"
  if [ "$MODE" = symlink ]; then
    ln -s "$src" "$dst"
  else
    cp -R "$src" "$dst"
  fi
  say "  install  $label"
}

say "codex-config install ($MODE${DRY:+, dry run}) -> $CODEX_HOME"

# --- skills shared with Claude Code ----------------------------------
# Only directories holding a SKILL.md; claude-config/skills also has
# loose notes and a `synced' staging dir that are not skills.
say "skills (shared with claude-config):"
for d in "$CC"/skills/*/; do
  name="$(basename "$d")"
  [ -f "$d/SKILL.md" ] || { say "  skip     $name (no SKILL.md)"; continue; }
  install_one "${d%/}" "$CODEX_HOME/skills/$name" "$name"
done

# --- skills generated from CC slash commands -------------------------
say "skills (generated from claude-config/commands):"
if [ -d "$GEN/skills" ]; then
  for d in "$GEN"/skills/*/; do
    name="$(basename "$d")"
    install_one "${d%/}" "$CODEX_HOME/skills/$name" "$name"
  done
else
  say "  skip     none generated yet (run: python gen.py)"
fi

# --- subagents --------------------------------------------------------
say "agents:"
for f in "$GEN"/agents/*.toml; do
  [ -e "$f" ] || { say "  skip     none generated yet"; break; }
  install_one "$f" "$CODEX_HOME/agents/$(basename "$f")" "$(basename "$f")"
done

# --- global instructions ---------------------------------------------
say "instructions:"
install_one "$GEN/AGENTS.md" "$CODEX_HOME/AGENTS.md" "AGENTS.md"

# --- hooks ------------------------------------------------------------
say "hooks:"
install_one "$GEN/hooks.json" "$CODEX_HOME/hooks.json" "hooks.json"

say ""
say "installed. Codex only runs a hooks.json you have TRUSTED:"
say "  start \`codex' interactively once and approve the hooks prompt,"
say "  then check payloads land in $CODEX_HOME/hook-payloads/."
