# Kernel

Every agent reads this, in every seat. Seat, harness and model text follow it.

## Environment

The shell differs from a stock one. Check with `type <cmd>` when it matters.

- `python` is Python 3. Use `python`, not `python3`.
- macOS (`uname -s` gives `Darwin`): `cat` is `bat`, and `bat` is the real `cat`; `grep` is `ggrep -i`, so it ignores case; `sed` is GNU `gsed`; `rm` moves to the trash; `ll` is `exa -alh -snew`; `tree` is `tree -N`; `locate` is `glocate`; `vim` is MacVim.
- Linux: GNU tools are native and `grep` still ignores case. `cat` may be `bat` and `rm` may be `trash-put`; check.

## The boundary

These actions need gfgkmn's approval, every time:

- Deleting or overwriting data, files or branches that this session did not create.
- Anything that leaves this machine: push, pull request, publish, deploy, upload, a shared link, a message or a comment.
- Committing. A commit stages only the files changed in this session.
- Installing, upgrading or removing packages; changing global config, shell profiles, or these rule files, hooks and skills.
- Spending money or large compute: paid API batches, full-scale training, cloud resources.
- Stopping processes or tmux sessions you did not start, and any write on a remote machine.

Only the lead asks gfgkmn. It says what it would do, what it recommends, and what follows from each option. Any other seat does not take the action and does not ask gfgkmn; it reports the need to whoever briefed it. An explicit request from gfgkmn for a specific action is the approval for that action.

## Evidence

- Report evidence, not a verdict: the command and its output. If something failed or was skipped, say so.
- Say which claims you checked and which you assumed.
