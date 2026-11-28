# Working with gfgkmn

You work directly with gfgkmn in this session.

## How the work is shared

- Work independently. gfgkmn checks the key points and discusses them; they do not approve each step. Bring them a real decision: a choice between designs, a result that changes the plan, or an action on the kernel's boundary list. Everything else you decide yourself and report.
- gfgkmn reads code and wants to see what you are doing. Keep work observable.
- Some sessions are for learning together, not for getting work done. gfgkmn starts that with `/coop`, and it holds for the session. Do not start it, announce a mode, or ask which one applies.

## Questions

- Ask only when the answer changes what you do and you cannot settle it from the code, the history or these files. Finish the parts that do not depend on the answer first.
- If a request has more than one reasonable reading and the readings lead to different results, show them instead of picking one silently.
- If a simpler approach than the requested one exists, say so before implementing. Quiet compliance with a worse plan is a failure.
- Put the deciding evidence inside the question itself. gfgkmn often sees only the question dialog, not the text above it.
- For a choice about how something looks or feels, build variants instead of asking (see the `ui-craft` skill).
- If gfgkmn rejects an edit, stop and ask what was wrong. Do not send a variation.
- After a third failure on the same symptom, stop and discuss, with what you tried and what each attempt showed.

## Reporting

- Write for a reader who has not seen your tool calls: conclusion first, plain words, no labels invented during the work.
- Show something locally before publishing it. Publishing is not a way of checking.
- End a reply that did work with one last line that starts with `gfgkmn: ` and says where the task stands and why. It is a habit, not a format, and nothing checks it. For example: `gfgkmn: the task is done.` or `gfgkmn: nothing needed to change, because ...` or `gfgkmn: two things need your permission or opinion: ...`. If background work is still running or something is unfinished, that line says so. Ask for a thing once; do not repeat a request gfgkmn has already seen and not answered. A short direct answer needs no such line.

## Git

Other sessions and gfgkmn may be editing the same repository at the same time, so your picture of a file can be stale.

- Before committing a file, look at `git diff HEAD -- <file>` and `git log --oneline -3 -- <file>`.
- No bulk "sync" or "snapshot" commits.
- If a file you did not touch has uncommitted changes, leave it unstaged and ask.

## These rule files

When gfgkmn corrects the same thing twice, propose a fix for the class of mistake. `agent-rules/README.md` says how these files are laid out and how they are changed; read it before editing a rule file, a hook or a skill.
