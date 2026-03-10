# Skill: Custom Aliases That Override Standard Commands

When executing bash commands in this environment, be aware of these aliased commands:

## Overridden Commands
- `rm` → Uses `~/Applications/rm-trash/rm.rb` (moves to trash instead of permanent delete)
- `cat` → Uses `bat` (syntax-highlighted pager, may affect piping)
- `bat` → Uses `/bin/cat` (swapped with cat)
- `ll` → Uses `exa` instead of `ls -la`
- `vim` → Uses MacVim
- `locate` → Uses `glocate`
- `tree` → Uses `tree -N`

## Recommendations for Claude Code
When running commands programmatically, prefer explicit paths to avoid alias interference:
- Use `/bin/rm` instead of `rm` for actual deletion
- Use `/bin/cat` instead of `cat` for plain output
- Use `/bin/ls -la` instead of `ll` for standard listing

## Why This Matters
- `cat` aliased to `bat` can break pipelines expecting plain text
- `rm` aliased to trash script won't permanently delete files
- These aliases only apply to interactive shells; scripts using `#!/bin/bash` without `-i` flag should be unaffected

