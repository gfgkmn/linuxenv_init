# Shell Environment (Cross-Platform)

This config is shared across machines. Detect the current platform before applying aliases.

To check: `uname -s` returns `Darwin` (macOS) or `Linux`.

## macOS (Darwin)

Machine: MacBook Pro / Mac Mini, username `gfgkmn`.

On macOS, GNU tools are installed via Homebrew with `g` prefixes, and several commands are aliased:

| Typed command | Actual binary         | Note                              |
|---------------|-----------------------|-----------------------------------|
| `cat`         | `bat`                 | Swapped with `bat`                |
| `bat`         | `/bin/cat`            | The real cat                      |
| `grep`        | `ggrep -i`           | Case-insensitive GNU grep         |
| `sed`         | `gsed`               | GNU sed                           |
| `rm`          | `rm-trash`            | Moves to trash, does not delete   |
| `python`      | `python3`             | Always use `python`, never `python3` |
| `vim`         | MacVim                |                                   |
| `ll`          | `exa -alh -snew`     |                                   |
| `tree`        | `tree -N`             |                                   |
| `td`          | `tldr`                |                                   |
| `locate`      | `glocate`             |                                   |

## Linux

On Linux, GNU tools are native — no `g` prefixes needed.

| Typed command | Actual binary         | Note                              |
|---------------|-----------------------|-----------------------------------|
| `cat`         | `bat` (if installed)  | Check `which bat` first           |
| `grep`        | `grep -i`            | Native GNU grep, case-insensitive |
| `sed`         | `sed`                | Native GNU sed                    |
| `rm`          | `rm` or `trash-put`  | Check if `trash-cli` is installed |
| `python`      | `python3`             | Always use `python`, never `python3` |
| `ll`          | `exa -alh -snew` or `ls -alh` | Check if `exa`/`eza` is installed |
| `tree`        | `tree -N`             |                                   |

## Common (Both Platforms)

- `python` is linked to `python3` — always use `python`, never `python3`.
- Prefer dedicated tools (Read, Grep, Glob, Edit) over shell aliases when available.
- Avoid using aliased commands via Bash tool when dedicated tools exist.
