---
name: stop-slop
description: Strip AI tells from English prose. Manual only - run when the user types /stop-slop or asks for an anti-slop pass. Do NOT invoke on your own while drafting.
argument-hint: [file or section to clean]
allowed-tools: Read, Edit, Write, Grep, Bash
---

# Stop Slop (English)

Thin wrapper around Hardik Pandya's `stop-slop`, vendored pristine so it can be
updated from source. The rules live upstream; this file only says when to run
them and how.

**Do not paraphrase the rules from memory.** Read the vendored files first.

## Where the rules are

```
~/.claude/vendor/stop-slop/SKILL.md               core rules + scoring
~/.claude/vendor/stop-slop/references/phrases.md      banned phrases
~/.claude/vendor/stop-slop/references/structures.md   banned structures
~/.claude/vendor/stop-slop/references/examples.md     before/after pairs
```

Read `SKILL.md` always. Read `phrases.md` and `structures.md` when doing a full
pass; skim `examples.md` when calibration is unclear.

## Updating from upstream

```bash
git -C ~/.claude/vendor/stop-slop pull --ff-only
git -C ~/.claude/vendor/stop-slop log -1 --format='%h %ad %s' --date=short
```

The clone is never edited locally, so this always fast-forwards. If it ever
refuses, something wrote to the vendor directory; inspect with `git -C
~/.claude/vendor/stop-slop status` rather than forcing.

## Procedure

1. Read the vendored rule files.
2. Read the target text in full before editing anything.
3. Rewrite. Do not merely delete flagged words: a sentence that only had its
   adverbs removed usually still carries the pattern that made it slop.
4. Score the result on the five dimensions in the upstream SKILL.md
   (directness, rhythm, trust, authenticity, density). Below 35/50, revise.
5. Report what changed by category, not line by line.

## Scope

English prose only. For Chinese, use `stop-slop-zh`, which imports part of this
rule set, suppresses three rules that damage Chinese, and adds the
translationese layer this one has no concept of. Never apply the English rules
to Chinese text unchanged - see the suppression list in `stop-slop-zh`.

## Attribution

Upstream: https://github.com/hardikpandya/stop-slop by Hardik Pandya, MIT.
Vendored at `~/.claude/vendor/stop-slop`, unmodified.
