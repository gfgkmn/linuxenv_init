---
description: Search user prompts across all Claude Code sessions (fzf picker, resume selected)
---

## Session Search

Search every Claude Code session's user prompts for a keyword or regex, pick a match from an fzf list, and print the resume command.

Uses the `$ARGUMENTS` as the query. Since this needs fzf (real TTY), it must run in the user's terminal — tell the user exactly what to run:

### If no arguments

Show usage:
```
Usage: /search <query>         Literal substring match (case-insensitive)
       /search --regex <query> Regex match

Example:
  /search "how many tokens"
  /search --regex "claude.*api"

Run directly in terminal:
  python ~/.claude/scripts/session.py search "$ARGUMENTS"
```

### If arguments given

Tell the user to run in their terminal (fzf needs real TTY):
```
python ~/.claude/scripts/session.py search "$ARGUMENTS"
```

If `--regex` is in $ARGUMENTS, preserve that flag position:
```
python ~/.claude/scripts/session.py search <query> --regex
```

The picker shows matching sessions with hit counts and excerpts. On select, it prints the `cd <path> && claude --resume <UUID>` command to copy/paste.
