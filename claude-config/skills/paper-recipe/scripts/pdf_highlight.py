"""Locate phrases in a PDF via pdftotext -bbox.

Library used by inject_highlights.py. Coordinates from pdftotext use origin
top-left; PDF annotations use origin bottom-left, hence the y-flip in `quads`.

Standalone check:  python pdf_highlight.py <paper.pdf> "<phrase>" [page_hint]
"""

import html
import re
import subprocess
import sys
from xml.etree import ElementTree


def word_boxes(pdf_path):
    """Return {page_number: (height, [(text, x0, y0, x1, y1), ...])} top-left coords."""
    xml = subprocess.run(
        ["pdftotext", "-bbox", pdf_path, "-"],
        capture_output=True, text=True, check=True,
    ).stdout
    root = ElementTree.fromstring(xml)
    pages = {}
    for i, page in enumerate(root.iter("{http://www.w3.org/1999/xhtml}page"), start=1):
        height = float(page.get("height"))
        words = []
        for w in page.iter("{http://www.w3.org/1999/xhtml}word"):
            words.append((
                html.unescape(w.text or ""),
                float(w.get("xMin")), float(w.get("yMin")),
                float(w.get("xMax")), float(w.get("yMax")),
            ))
        pages[i] = (height, words)
    return pages


def norm(s):
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def find_phrase(pages, phrase, page_hint=None):
    """Find `phrase` as a run of consecutive words. Returns (page, [boxes])."""
    target = norm(phrase)
    order = sorted(pages)
    if page_hint and page_hint in pages:
        order = [page_hint] + [p for p in order if p != page_hint]
    for pno in order:
        _, words = pages[pno]
        for start in range(len(words)):
            acc = ""
            for end in range(start, min(start + 60, len(words))):
                acc += norm(words[end][0])
                if acc == target:
                    return pno, words[start:end + 1]
                if not target.startswith(acc):
                    break
    return None, None


def quads(page_height, boxes):
    """Group boxes into lines, return flat QuadPoints in bottom-left coords."""
    lines = {}
    for text, x0, y0, x1, y1 in boxes:
        key = round(y0 / 3.0)
        lines.setdefault(key, []).append((x0, y0, x1, y1))
    out = []
    for key in sorted(lines):
        xs0 = min(b[0] for b in lines[key])
        xs1 = max(b[2] for b in lines[key])
        ys0 = min(b[1] for b in lines[key])
        ys1 = max(b[3] for b in lines[key])
        top = page_height - ys0
        bot = page_height - ys1
        out.extend([xs0, top, xs1, top, xs0, bot, xs1, bot])
    return out


def main():
    pdf = sys.argv[1]
    phrase = sys.argv[2]
    hint = int(sys.argv[3]) if len(sys.argv) > 3 else None
    pages = word_boxes(pdf)
    pno, boxes = find_phrase(pages, phrase, hint)
    if not boxes:
        print(f"NOT FOUND: {phrase!r}")
        return 1
    print(f"FOUND on page {pno}: {' '.join(b[0] for b in boxes)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
