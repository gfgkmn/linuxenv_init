#!/usr/bin/env python
"""Switch Claude Code permission presets.

Presets:
  permissive — Write/Edit auto-allowed, no review
  audit      — Write/Edit auto-allowed, Emacs review on each edit
  strict     — Write/Edit require Claude Code approval prompt (no Emacs)

Usage:
    python preset_switch.py                # show current preset
    python preset_switch.py audit          # switch to audit mode
    python preset_switch.py toggle         # cycle through presets
"""

import json
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"
AUDIT_MARKER = Path.home() / ".claude" / ".audit-enabled"
WRITE_TOOLS = {"Write", "Edit", "MultiEdit"}

C_RESET = "\033[0m"
C_DIM = "\033[2m"
C_RED = "\033[31m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_CYAN = "\033[36m"
C_BOLD = "\033[1m"

PRESETS = ("permissive", "audit", "strict")


def load_settings() -> dict:
    if not SETTINGS_PATH.exists():
        return {"permissions": {"allow": [], "deny": []}}
    return json.loads(SETTINGS_PATH.read_text())


def save_settings(data: dict):
    SETTINGS_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def detect_preset(settings: dict) -> str:
    allow = set(settings.get("permissions", {}).get("allow", []))
    has_write = bool(WRITE_TOOLS & allow)
    audit_on = AUDIT_MARKER.exists()

    if has_write and audit_on:
        return "audit"
    elif has_write:
        return "permissive"
    else:
        return "strict"


def switch_to(settings: dict, preset: str) -> dict:
    allow = settings.setdefault("permissions", {}).setdefault("allow", [])

    if preset in ("permissive", "audit"):
        current = set(allow)
        for tool in ("Write", "Edit", "MultiEdit"):
            if tool not in current:
                try:
                    idx = allow.index("Grep") + 1
                except ValueError:
                    idx = len(allow)
                allow.insert(idx, tool)
    elif preset == "strict":
        settings["permissions"]["allow"] = [
            t for t in allow if t not in WRITE_TOOLS
        ]

    if preset == "audit":
        AUDIT_MARKER.touch()
    else:
        if AUDIT_MARKER.exists():
            AUDIT_MARKER.unlink()

    return settings


def main():
    settings = load_settings()
    current = detect_preset(settings)

    if len(sys.argv) < 2:
        colors = {"permissive": C_GREEN, "audit": C_CYAN, "strict": C_YELLOW}
        print(f"Current preset: {colors[current]}{C_BOLD}{current}{C_RESET}")
        print(f"\n  {C_GREEN}permissive{C_RESET}  Write/Edit auto-allowed, no review")
        print(f"  {C_CYAN}audit{C_RESET}       Write/Edit auto-allowed, Emacs review each edit")
        print(f"  {C_YELLOW}strict{C_RESET}      Write/Edit require Claude Code approval prompt")
        print(f"\nUsage: {sys.argv[0]} [permissive|audit|strict|toggle]")
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
        print(f"Already on {colors[current]}{C_BOLD}{target}{C_RESET}")
        return

    settings = switch_to(settings, target)
    save_settings(settings)

    icons = {"permissive": "🔓", "audit": "🔍", "strict": "🔒"}
    colors = {"permissive": C_GREEN, "audit": C_CYAN, "strict": C_YELLOW}
    descs = {
        "permissive": "Write/Edit auto-allowed, no review",
        "audit": "Write/Edit auto-allowed, Emacs review each edit",
        "strict": "Write/Edit require Claude Code approval prompt",
    }

    print(f"{icons[target]} Switched to {colors[target]}{C_BOLD}{target}{C_RESET}")
    print(f"  {descs[target]}")

    needs_restart = (target == "strict") != (current == "strict")
    if needs_restart:
        print(f"\n{C_RED}{C_BOLD}⚠  Restart Claude Code now to apply!{C_RESET}")
        print(f"{C_DIM}   Permission changes require restart. Run /exit then relaunch.{C_RESET}")
    else:
        print(f"\n{C_GREEN}✓ Active immediately (no restart needed){C_RESET}")


if __name__ == "__main__":
    main()
