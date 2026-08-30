"""Inject highlight annotations into a copy of a paper PDF.

Usage:  python inject_highlights.py <src.pdf> <out.pdf> <claims.json>

claims.json: [{"key": "...", "phrase": "...", "page": 7, "note": "..."}, ...]
`page` is a hint only; the phrase search falls back to a full scan.
"""

import json
import sys

import pypdf
from pypdf.annotations import Highlight
from pypdf.generic import ArrayObject, FloatObject

from pdf_highlight import find_phrase, quads, word_boxes


def main():
    src_pdf, out_path, claims_path = sys.argv[1], sys.argv[2], sys.argv[3]
    claims = json.load(open(claims_path))
    pages = word_boxes(src_pdf)
    writer = pypdf.PdfWriter(clone_from=src_pdf)

    placed, missing = [], []
    for c in claims:
        pno, boxes = find_phrase(pages, c["phrase"], c.get("page"))
        if not boxes:
            missing.append(c["key"])
            continue
        height, _ = pages[pno]
        q = quads(height, boxes)
        xs = [q[i] for i in range(0, len(q), 2)]
        ys = [q[i] for i in range(1, len(q), 2)]
        hl = Highlight(
            rect=(min(xs), min(ys), max(xs), max(ys)),
            quad_points=ArrayObject([FloatObject(v) for v in q]),
            highlight_color="ffe066",
        )
        # `contents` comes back from the reference manager's annotation
        # extraction, so the note key rides along in it.
        hl[pypdf.generic.NameObject("/Contents")] = pypdf.generic.TextStringObject(
            c.get("note", c["key"])
        )
        writer.add_annotation(page_number=pno - 1, annotation=hl)
        placed.append((c["key"], pno))

    with open(out_path, "wb") as fh:
        writer.write(fh)

    print(f"placed: {len(placed)}  missing: {len(missing)}")
    for key, pno in placed:
        print(f"  p{pno:>2}  {key}")
    for key in missing:
        print(f"  MISSING  {key}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
