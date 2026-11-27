# codex-config — the same abilities, for Codex

`claude-config/` stays the single source of truth. This directory translates
it into the formats Codex reads, and links the result into `$CODEX_HOME`
(`~/.codex`). Nothing here is hand-maintained except `hooks.json` and the
scripts in `hooks/`.

```bash
python gen.py      # claude-config -> generated/
bash install.sh    # generated/ + claude-config/skills -> ~/.codex
```

Both are idempotent. `install.sh --dry-run` shows what would change;
`--copy` uses copies instead of symlinks (only needed if a future Codex
stops following links — today it follows them).

## What maps to what

| Claude Code | Codex | How |
|---|---|---|
| `skills/<n>/SKILL.md` | `~/.codex/skills/<n>` | **symlinked** — identical format, one file serves both |
| `commands/<n>.md` (slash commands) | `~/.codex/skills/<n>` | generated: Codex has no slash commands, skills are its invocable unit |
| `agents/<n>.md` | `~/.codex/agents/<n>.toml` | generated: `name` / `description` / `developer_instructions` |
| `agent-rules/` kernel + seats + `harness/codex.md` + `models/gpt-family.md` | `~/.codex/AGENTS.md` | generated as one joined file — Codex has no `@file` syntax. `CLAUDE.md` imports the same kernel and seats with Claude's own harness and model files |
| `agent-rules/` kernel + seats + `harness/agy.md` + `models/gemini-family.md` | `generated/agy/AGENTS.md` | generated the same way for Antigravity |
| `agent-rules/subagents.map` | appended to each listed subagent's `.toml` | Claude Code supplies these files through a hook; Codex has none wired |
| `settings.json` hooks | `~/.codex/hooks.json` | same schema, same event names, **but trust-gated** (below) |
| `settings.json` permissions | `config.toml` sandbox / `[projects.*] trust_level` | not 1:1, not translated |
| `statusline-command.sh` | — | no Codex equivalent |

What is lost in translation, and visible in each generated file's header:
a subagent's `tools:` and `model:` have no Codex equivalent and are dropped,
so a Codex subagent runs with the default model and full tool access.

## Hooks are trust-gated

Codex implements the same hook events as Claude Code — `PreToolUse`,
`PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`,
`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `SubagentStart`,
`SubagentStop`, `Stop` — with the same stdin-JSON / stdout-JSON contract
and `hookSpecificOutput`. But a `hooks.json` it has not been told to trust
is **silently skipped**, and `codex exec` cannot prompt, so hooks never run
non-interactively until trust is granted once:

```bash
codex          # interactively, then approve the hooks prompt
ls ~/.codex/hook-payloads/   # should start filling up
```

Trust is recorded per hooks-file hash, so **editing `hooks.json` revokes it**
and it has to be re-approved.

The payload field names also differ from Claude Code's: there is a `turn_id`
where CC has `prompt_id`, there is **no** `last_assistant_message` (read the
transcript instead), and the tool names are `exec` / `apply_patch` / `js`,
not `Bash` / `Edit` / `Write`. That is why `hooks.json` currently wires only
`hooks/capture-payload.sh`: it records real payloads and decides nothing.
The enforcement hooks (`enforce-tmux.sh`, `audit_edit.py`,
`cc-changes-log.sh`) are shared with Claude Code and read only `tool_name`
and `tool_input`, so they port once a captured payload confirms the shape.

## Where Codex keeps a session

Useful when wiring tooling against it:

- transcript: `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<ISO>-<uuid>.jsonl`,
  records shaped `{timestamp, ordinal, type, payload}`
- the same content, indexed: `~/.codex/sqlite/` — `thread_turns` (one row per
  turn, with `status` and `final_agent_item_id`) and `thread_items`
- live sessions, and sending into one: the app-server protocol
  (`thread/list`, `turn/start`, `turn/steer`) over a control socket, or
  `codex queue --thread <uuid> --message <text>` from the shell
