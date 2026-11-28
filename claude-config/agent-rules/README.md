# The rule files

This file is for whoever changes the rules. No agent loads it by default.

## Layout

| File | Who reads it | What it holds |
|---|---|---|
| `kernel.md` | every agent | the environment, the boundary, evidence |
| `craft/thinking.md`, `craft/doing.md` | every main session; subagents where listed | how to think and how to execute, with no role in it |
| `solo.md` | a session that works directly with gfgkmn | sharing the work, questions, reporting, git |
| `team/<role>.md` | a session or subagent that holds that role in a team | only what the role adds or forbids |
| `harness/<tool>.md` | sessions in that tool | what only that tool allows or needs |
| `models/<family>.md` | sessions on that model family | tendencies of that family, each with its source |
| `roster.md` | the lead of a team | what gfgkmn has tested about each model |

Principles and their particular uses stay apart. `solo.md` and the team files describe roles; what gfgkmn is as a person (a researcher, learning) lives in the `/coop` command and loads only when gfgkmn starts it.

## How a session gets its files

- Claude Code: `CLAUDE.md` imports the kernel, the craft files, the harness file and the model file. `hooks/session-role.sh` then adds the files that `roles.map` lists for the session's role. The role is `$AGENT_ROLE`, else the `claude --agent` name, else `solo`. A solo session never sees `team/`.
- Claude Code subagents: `hooks/subagent-rules.sh` adds the files that `subagents.map` lists for the subagent type.
- Codex and Antigravity: `codex-config/gen.py` joins the files into one `AGENTS.md` per tool.

A new role is one file in `team/` and one line in `roles.map`. A new tool is one file in `harness/` and one entry in `gen.py`.

## Changing the rules

- **Hooks guard actions, never replies.** A hook may stop or question something the agent does to the world: running, writing, installing, sending. It must not dictate the form of a reply or a way of thinking. A check on prose makes the agent write for the check, and the checked rules then crowd out the judgement the task needed.
- For a mistake in an action, prefer in this order: a mechanical check (hook, test, lint, deny rule); a structure that makes the mistake impossible; a line of prose only if neither works.
- For a mistake of judgement or communication, a hook is the wrong tool. Give the reason in a sentence, or one example, in the narrowest file. If that does not help, the cause is usually elsewhere: too many rules, or the wrong context.
- Every rule the agent must satisfy on every reply is a cost on every reply. Add one only when its absence has cost more.
- A line of prose goes in the narrowest file that fits: a model file if only one model family does it, a harness file if only one tool allows it, a role file if it belongs to the role. The kernel changes last.
- Once a check guards a rule, cut the prose to one line that names the check.
- Each rule states its scope and its reason, so it can be dropped when the reason is gone. No incident stories and no dates.
- No file here may be named `claude.md`, `agents.md` or `gemini.md`: on a case-insensitive disk a tool loads it on its own.
