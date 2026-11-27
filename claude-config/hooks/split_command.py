#!/usr/bin/env python
"""Split a shell command into the simple commands it would run.

Used by enforce-tmux.sh. Reads one command from stdin and prints one
normalized simple command per line, so the hook's `^pattern` checks see
`python train.py` whether it arrives bare or as
`cd x && FOO=1 time /usr/bin/python3 train.py`.

Not covered: commands nested in another program's arguments
(`ssh host '...'`, `xargs`, `find -exec`) and `$(...)` inside double quotes.
"""

import re
import shlex
import sys

SEPARATORS = ";\n|&()`"
KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "!", "{"}
WRAPPERS = {"time", "nohup", "exec", "command", "builtin", "sudo", "env",
            "nice", "caffeinate", "stdbuf"}
WRAPPER_OPTS_WITH_VALUE = {"-n", "-u", "-g"}
RUNNERS = {("uv", "run"), ("poetry", "run"), ("pipenv", "run"),
           ("pdm", "run"), ("conda", "run"), ("mamba", "run")}
RUNNER_OPTS_WITH_VALUE = {"-n", "-p", "--name", "--prefix", "--with",
                          "--python", "--project", "--directory"}
SHELLS = {"bash", "sh", "zsh"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PYTHON = re.compile(r"^python[0-9.]*$")
HEREDOC = re.compile(
    r"<<-?[ \t]*(['\"]?)(\w+)\1([^\n]*)\n.*?\n[ \t]*\2[ \t]*(?=\n|$)", re.S)
MAX_DEPTH = 3


def strip_heredocs(cmd):
    """Drop heredoc bodies: they are input to a command, not commands."""
    return HEREDOC.sub(lambda m: " " + m.group(3), cmd)


def split_top(cmd):
    """Split on unquoted ; && || | & newline ( ) and backtick."""
    segs, cur, quote, i, n = [], [], None, 0, len(cmd)
    while i < n:
        c = cmd[i]
        if quote == "'":
            if c == "'":
                quote = None
            cur.append(c)
        elif quote == '"':
            if c == "\\" and i + 1 < n:
                cur.append(cmd[i:i + 2])
                i += 2
                continue
            if c == '"':
                quote = None
            cur.append(c)
        elif c == "\\" and i + 1 < n:
            if cmd[i + 1] != "\n":          # backslash-newline joins lines
                cur.append(cmd[i:i + 2])
            i += 2
            continue
        elif c in "'\"":
            quote = c
            cur.append(c)
        elif c in SEPARATORS:
            segs.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    segs.append("".join(cur))
    return segs


def words(seg):
    try:
        return shlex.split(seg, posix=True)
    except ValueError:
        return seg.split()


def expand(text, depth):
    out = []
    for seg in split_top(strip_heredocs(text)):
        out.extend(normalize(seg, depth))
    return out


def normalize(seg, depth=0):
    """Strip what stands in front of the real command; return 0+ commands."""
    w = words(seg)
    while w:
        head = w[0]
        if head in KEYWORDS or ASSIGN.match(head):
            w = w[1:]
            continue
        base = head.rsplit("/", 1)[-1]
        if base in WRAPPERS:
            w = w[1:]
            while w and (w[0].startswith("-") or ASSIGN.match(w[0])):
                w = w[2:] if w[0] in WRAPPER_OPTS_WITH_VALUE else w[1:]
            continue
        if len(w) >= 2 and (base, w[1]) in RUNNERS:
            w = w[2:]
            while w and w[0].startswith("-"):
                w = w[2:] if w[0] in RUNNER_OPTS_WITH_VALUE else w[1:]
            continue
        if base in SHELLS and depth < MAX_DEPTH:
            # bash -c "…": the string is itself a command line
            for i in range(1, len(w) - 1):
                x = w[i]
                if x.startswith("-") and not x.startswith("--") and "c" in x:
                    return expand(w[i + 1], depth + 1)
        if base == "eval" and depth < MAX_DEPTH and len(w) > 1:
            return expand(" ".join(w[1:]), depth + 1)
        w = ["python" if PYTHON.match(base) else base] + w[1:]
        break
    return [" ".join(w).replace("\n", " ")] if w else []


if __name__ == "__main__":
    for line in expand(sys.stdin.read(), 0):
        print(line)
