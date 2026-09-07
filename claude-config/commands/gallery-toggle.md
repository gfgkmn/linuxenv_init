---
description: Toggle unattended screenshot galleries (screenshot-review skill)
---

Flips whether the `screenshot-review` skill may capture and publish a gallery
without asking.

OFF (default) — semi-auto: the agent asks before capturing a batch and before
publishing. ON — full auto: it builds, captures and publishes unprompted,
which is what you want while asleep or away from the desk.

State is the presence of `~/.claude/gallery-enabled`. `cc-gallery.py --auto`
exits non-zero while the file is absent, so the mode is enforced by the tool
rather than by the agent's discretion. Pass `on`, `off`, or `status` to set it
explicitly; with no argument it toggles.

!`~/.claude/scripts/cc-gallery-toggle.sh $ARGUMENTS 2>&1`
