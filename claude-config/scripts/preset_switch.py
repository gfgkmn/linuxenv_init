#!/usr/bin/env python
"""Switch Claude Code audit preset (session-scoped via env var).

Presets:
  permissive — allow all edits, no review
  audit      — Emacs review on each edit
  strict     — terminal prompt per edit (y/n/a/e)

The preset is stored in CLAUDE_AUDIT_MODE env var, scoped to the session.
No restart needed. No global settings changes.

Usage:
    python preset_switch.py                # show current preset
    python preset_switch.py audit          # switch to audit mode
    python preset_switch.py toggle         # cycle through presets
"""

import os
import sys

C_RESET = "\033[0m"
C_DIM = "\033[2m"
C_RED = "\033[31m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_CYAN = "\033[36m"
C_BOLD = "\033[1m"

PRESETS = ("permissive", "audit", "strict")


def get_current() -> str:
    return os.environ.get("CLAUDE_AUDIT_MODE", "permissive")


def main():
    current = get_current()

    if len(sys.argv) < 2:
        colors = {"permissive": C_GREEN, "audit": C_CYAN, "strict": C_YELLOW}
        print(f"Current preset: {colors.get(current, '')}{C_BOLD}{current}{C_RESET}")
        print(f"\n  {C_GREEN}permissive{C_RESET}  Allow all edits, no review")
        print(f"  {C_CYAN}audit{C_RESET}       Emacs review each edit (C-c C-c / C-c C-k)")
        print(f"  {C_YELLOW}strict{C_RESET}      Terminal prompt per edit (y/n/a/e)")
        print(f"\nUsage: {sys.argv[0]} [permissive|audit|strict|toggle]")
        print(f"\n{C_DIM}Session-scoped via CLAUDE_AUDIT_MODE env var.{C_RESET}")
        return

    target = sys.argv[1].lower().strip()

    if target == "toggle":
        idx = PRESETS.index(current) if current in PRESETS else 0
        target = PRESETS[(idx + 1) % len(PRESETS)]

    if target not in PRESETS:
        for name in PRESETS:
            if name.startswith(target) or target.startswith(name[:3]):
                target = name
                break
        else:
            print(f"{C_RED}Unknown preset: {target}{C_RESET}")
            print(f"Available: {', '.join(PRESETS)}, toggle")
            sys.exit(1)

    if target == current:
        colors = {"permissive": C_GREEN, "audit": C_CYAN, "strict": C_YELLOW}
        print(f"Already on {colors.get(current, '')}{C_BOLD}{target}{C_RESET}")
        return

    icons = {"permissive": "🔓", "audit": "🔍", "strict": "🔒"}
    colors = {"permissive": C_GREEN, "audit": C_CYAN, "strict": C_YELLOW}
    descs = {
        "permissive": "Allow all edits, no review",
        "audit": "Emacs review each edit",
        "strict": "Terminal prompt per edit (y/n/a/e)",
    }

    print(f"{icons[target]} Switched to {colors[target]}{C_BOLD}{target}{C_RESET}")
    print(f"  {descs[target]}")

    # Output the env var command for the slash command to pick up
    print(f"\nCLAUDE_AUDIT_MODE={target}")
    print(f"\n{C_GREEN}✓ Active immediately (no restart needed){C_RESET}")


if __name__ == "__main__":
    main()
