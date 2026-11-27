# Shell Environment (Cross-Platform)

This config is shared across machines. Detect the current platform before applying aliases.

To check: `uname -s` returns `Darwin` (macOS) or `Linux`.

## macOS (Darwin)

Machine: MacBook Pro (username `gfgkmn`) / Mac Mini (username `fhqgqj`). Check with `scutil --get ComputerName`.

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

### Default Python (Homebrew)

`python` and `python3` in `/opt/homebrew/bin` are links made by `stick-python <version>` (`~/Applications/bin/stick-python`). The version is per machine:

| Machine      | Version | Command              |
|--------------|---------|----------------------|
| MacBook Pro  | 3.10    | `stick-python 3.10`  |
| Mac Mini     | 3.14    | `stick-python 3.14`  |

- `brew upgrade` of a python formula re-links `python3` to the newest python and leaves no plain `python`. Hooks then fail with `python: command not found` (exit 127), for example `PreToolUse:Write hook failed`.
- `morning-update` re-links after its brew step (step 1d). If the error shows up between runs, run the `stick-python` command for the machine. Do not edit hook commands to `python3`.
- `python` as a zsh alias exists only in interactive shells. Hooks and scripts need the real link.

### Screenshots from the other machine

CleanShot saves to `~/Temp/CleanShot/` on both machines. The user names are different: `gfgkmn` on the MacBook Pro (ssh host `macbook`), `fhqgqj` on the Mac Mini.

- When the user gives a path under `/Users/gfgkmn/Temp/CleanShot/` and the session runs on the Mac Mini, the file is on the MacBook. Do not report "file does not exist". Copy it, then read the local copy:
  `scp macbook:'~/Temp/CleanShot/<file>' ~/Temp/CleanShot/`
- Apply the same rule to any other `/Users/gfgkmn/...` path given on the Mac Mini: fetch it from `macbook` first.

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
