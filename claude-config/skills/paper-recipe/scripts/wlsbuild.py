"""Transcode a UTF-8 Wolfram source into the \\:XXXX escapes wolframscript needs.

wolframscript reads .wls files as Latin-1, so any CJK written literally comes out
as mojibake. Author in `*.src.wls` (readable), build to `*.wls` (escaped).

    python wlsbuild.py figures.src.wls figures.wls
"""

import sys


def escape(text):
    out = []
    for ch in text:
        o = ord(ch)
        if o < 128:
            out.append(ch)
        elif o <= 0xFFFF:
            out.append(f"\\:{o:04x}")
        else:  # outside the BMP -> surrogate pair
            v = o - 0x10000
            out.append(f"\\:{0xD800 + (v >> 10):04x}\\:{0xDC00 + (v & 0x3FF):04x}")
    return "".join(out)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    raw = open(src, encoding="utf-8").read()
    esc = escape(raw)
    open(dst, "w", encoding="ascii").write(esc)
    n = sum(1 for c in raw if ord(c) > 127)
    print(f"{src} -> {dst}   escaped {n} non-ASCII chars")


if __name__ == "__main__":
    main()
