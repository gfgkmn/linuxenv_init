---
description: Today's English drill — real utterances of yours, judged live
---

!`~/.claude/skills/english-lab/english.py update --quiet 2>&1 | tail -3; ~/.claude/skills/english-lab/english.py drill 2>&1`

Read all six utterances. Teach the two or three with the most teachable gap;
say so in three words for any that are already fine. Aim at range, never at
morphology — plural `-s`, articles and third-person `-s` are off the table.

For each: the version a wider-range speaker would produce, plus one line of
Chinese naming the gap. Record it with `english.py add`. Tell the user to
**say** the rewrites out loud.

Also handle the due items shown, by their state (已经用上了 / 复习 / 卡住了).
