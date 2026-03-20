#!/usr/bin/env python
"""Switch Claude Code permission presets by toggling write/edit permissions.

Presets:
  permissive (default) — Write, Edit, MultiEdit allowed
  strict               — Write, Edit, MultiEdit require approval

Usage:
    python preset_switch.py                # show current preset
    python preset_switch.py strict         # switch to strict
    python preset_switch.py permissive     # switch to permissive
    python preset_switch.py toggle         # toggle between presets
"""

import json
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"
WRITE_TOOLS = {"Write", "Edit", "MultiEdit"}

# ANSI
C_RESET = "\033[0m"
C_DIM = "\033[2m"
C_RED = "\033[31m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_BOLD = "\033[1m"


def load_settings() -> dict:
    if not SETTINGS_PATH.exists():
        return {"permissions": {"allow": [], "deny": []}}
    return json.loads(SETTINGS_PATH.read_text())


def save_settings(data: dict):
    SETTINGS_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def detect_preset(settings: dict) -> str:
    allow = set(settings.get("permissions", {}).get("allow", []))
    if WRITE_TOOLS & allow:
        return "permissive"
    return "strict"


def switch_to(settings: dict, preset: str) -> dict:
    allow = settings.setdefault("permissions", {}).setdefault("allow", [])

    if preset == "strict":
        # Remove write tools from allow list
        settings["permissions"]["allow"] = [
            t for t in allow if t not in WRITE_TOOLS
        ]
    elif preset == "permissive":
        # Add write tools back (in original order, after Grep)
        current = set(allow)
        for tool in ("Write", "Edit", "MultiEdit"):
            if tool not in current:
                # Insert after Grep if present, else append
                try:
                    idx = allow.index("Grep") + 1
                except ValueError:
                    idx = len(allow)
                allow.insert(idx, tool)

    return settings


def main():
    settings = load_settings()
    current = detect_preset(settings)

    if len(sys.argv) < 2:
        # Show current
        color = C_GREEN if current == "permissive" else C_YELLOW
        print(f"Current preset: {color}{C_BOLD}{current}{C_RESET}")
        print(f"\nUsage: {sys.argv[0]} [strict|permissive|toggle]")
        return

    target = sys.argv[1].lower().strip()

    if target == "toggle":
        target = "strict" if current == "permissive" else "permissive"

    # Fuzzy match: accept prefixes and common typos
    if target not in ("strict", "permissive", "toggle"):
        for name in ("strict", "permissive"):
            if name.startswith(target) or target.startswith(name[:3]):
                target = name
                break
        else:
            print(f"{C_RED}Unknown preset: {target}{C_RESET}")
            print("Available: strict, permissive, toggle")
            sys.exit(1)

    if target == current:
        color = C_GREEN if current == "permissive" else C_YELLOW
        print(f"Already on {color}{C_BOLD}{target}{C_RESET}")
        return

    settings = switch_to(settings, target)
    save_settings(settings)

    color = C_GREEN if target == "permissive" else C_YELLOW
    icon = "🔓" if target == "permissive" else "🔒"
    print(f"{icon} Switched to {color}{C_BOLD}{target}{C_RESET}")

    if target == "strict":
        print(f"  Write, Edit, MultiEdit now require approval")
    else:
        print(f"  Write, Edit, MultiEdit are auto-allowed")

    print(f"\n{C_RED}{C_BOLD}⚠  Restart Claude Code now to apply!{C_RESET}")
    print(f"{C_DIM}   Permissions are loaded at startup and cannot be changed mid-session.{C_RESET}")
    print(f"{C_DIM}   Run /exit then relaunch claude.{C_RESET}")


if __name__ == "__main__":
    main()
