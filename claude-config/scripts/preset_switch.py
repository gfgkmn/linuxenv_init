#!/usr/bin/env python
"""Switch Claude Code audit preset (project-scoped).

Presets:
  permissive — allow all edits, no review
  audit      — Emacs review on each edit

Mode is stored in <project>/.claude/.audit-mode.
Each project has its own mode. No restart needed.

Usage:
    python preset_switch.py                # show current preset
    python preset_switch.py audit          # switch to audit mode
    python preset_switch.py toggle         # toggle between presets
"""

import sys
from pathlib import Path

AUDIT_MODE_FILE = Path.cwd() / ".claude" / ".audit-mode"

C_RESET = "\033[0m"
C_DIM = "\033[2m"
C_RED = "\033[31m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_CYAN = "\033[36m"
C_BOLD = "\033[1m"

PRESETS = ("permissive", "audit")


def get_current() -> str:
    try:
        mode = AUDIT_MODE_FILE.read_text().strip()
        if mode in PRESETS:
            return mode
    except OSError:
        pass
    return "permissive"


def set_mode(mode: str):
    AUDIT_MODE_FILE.parent.mkdir(parents=True, exist_ok=True)
    AUDIT_MODE_FILE.write_text(mode + "\n")


def main():
    current = get_current()

    if len(sys.argv) < 2:
        colors = {"permissive": C_GREEN, "audit": C_CYAN}
        print(f"Current preset: {colors.get(current, '')}{C_BOLD}{current}{C_RESET}")
        print(f"\n  {C_GREEN}permissive{C_RESET}  Allow all edits, no review")
        print(f"  {C_CYAN}audit{C_RESET}       Emacs review each edit (C-c C-c / C-c C-k)")
        print(f"\nUsage: {sys.argv[0]} [permissive|audit|toggle]")
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
        colors = {"permissive": C_GREEN, "audit": C_CYAN}
        print(f"Already on {colors.get(current, '')}{C_BOLD}{target}{C_RESET}")
        return

    set_mode(target)

    icons = {"permissive": "🔓", "audit": "🔍"}
    colors = {"permissive": C_GREEN, "audit": C_CYAN}
    descs = {
        "permissive": "Allow all edits, no review",
        "audit": "Emacs review each edit",
    }

    print(f"{icons[target]} Switched to {colors[target]}{C_BOLD}{target}{C_RESET}")
    print(f"  {descs[target]}")
    print(f"\n{C_GREEN}✓ Active immediately (no restart needed){C_RESET}")


if __name__ == "__main__":
    main()
