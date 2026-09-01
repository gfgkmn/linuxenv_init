#!/usr/bin/env python3
"""Build a self-contained review gallery from captured screenshots.

The gallery is meant to be published as an Artifact and flipped through on a
phone: one screen per card, a note on what changed, and a Ship / Send back
verdict. Images are downscaled and inlined as data URIs because an Artifact
must be self-contained and stay under the 16 MB page cap.

Manifest (JSON) — a list of entries:
  [{"path": "/abs/shot.png", "name": "Timeline", "group": "macOS",
    "note": "Running entry grows in place."}, ...]
"group" and "note" are optional.

Usage:
  cc-gallery.py MANIFEST.json OUT.html [--title T] [--build B] [--width 900]
  cc-gallery.py --from-dir DIR OUT.html      build a manifest from a directory
"""

import argparse, base64, html, json, os, subprocess, sys, tempfile

JPEG_QUALITY = "72"
CAP_BYTES = 16 * 1024 * 1024
BUDGET = int(CAP_BYTES * 0.85)          # leave room for markup and fonts


def dimensions(path):
    r = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                       capture_output=True, text=True)
    w = h = 0
    for line in r.stdout.splitlines():
        if "pixelWidth:" in line:
            w = int(line.split(":")[1])
        elif "pixelHeight:" in line:
            h = int(line.split(":")[1])
    return w, h


def encode(path, base_width):
    """Return (data URI, is_portrait).

    A desktop window and a phone screen carry very different amounts of detail
    per pixel, so they are not resampled to the same width: a 3840px-wide Mac
    window shrunk to 900px turns its text to mush, while a phone screen at that
    width is already generous. Scale on the long edge instead, and give
    landscape captures roughly double the budget.
    """
    w, h = dimensions(path)
    portrait = h > w
    long_edge = base_width if portrait else int(base_width * 2)
    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, "s.jpg")
        r = subprocess.run(
            ["sips", "-Z", str(long_edge), "-s", "format", "jpeg",
             "-s", "formatOptions", JPEG_QUALITY, path, "--out", out],
            capture_output=True)
        if r.returncode != 0 or not os.path.exists(out):
            raise RuntimeError("sips failed on %s: %s"
                               % (path, r.stderr.decode()[:200]))
        with open(out, "rb") as fh:
            uri = "data:image/jpeg;base64," + base64.b64encode(fh.read()).decode()
    return uri, portrait


def card(e, uri, portrait):
    name = html.escape(e.get("name") or os.path.basename(e["path"]))
    note = html.escape(e.get("note") or "")
    meta = html.escape(e.get("meta") or "")
    stale = "-offscreen" in e["path"]
    warn = ('<span class="warn" title="Window was off-screen when captured; '
            'this may be a cached frame">may be stale</span>' if stale else "")
    # Every thumbnail gets the same box; the image is contained inside it. A
    # tall phone screen and a wide Mac window then occupy equal card area
    # instead of one dwarfing the other in a shared grid.
    return f"""<article class="card" data-orient="{'portrait' if portrait else 'landscape'}">
  <button class="shot" aria-label="Enlarge {name}"><img src="{uri}" alt="{name}" loading="lazy"></button>
  <div class="body">
    <h3 class="name">{name}{warn}</h3>
    {f'<div class="meta mono">{meta}</div>' if meta else ''}
    {f'<p class="changed">{note}</p>' if note else ''}
    <div class="actions">
      <button class="verdict" data-v="pass">Ship</button>
      <button class="verdict" data-v="flag">Send back</button>
      <span class="note"></span>
    </div>
  </div>
</article>"""


def build(entries, out_path, title, build_label, width):
    groups, total = {}, 0
    for e in entries:
        if not os.path.exists(e["path"]):
            print("  skip (missing): %s" % e["path"], file=sys.stderr)
            continue
        uri, portrait = encode(e["path"], width)
        total += len(uri)
        if total > BUDGET:
            print("  stopping: %d bytes of images would exceed the page cap"
                  % total, file=sys.stderr)
            break
        groups.setdefault(e.get("group") or "Screens", []).append(
            card(e, uri, portrait))

    sections = "\n".join(
        f'<section class="group"><h2>{html.escape(g)}</h2><div class="rule"></div>'
        f'<div class="grid">{"".join(cs)}</div></section>'
        for g, cs in groups.items())
    n = sum(len(c) for c in groups.values())

    doc = TEMPLATE.replace("{{TITLE}}", html.escape(title)) \
                  .replace("{{BUILD}}", html.escape(build_label)) \
                  .replace("{{COUNT}}", str(n)) \
                  .replace("{{SECTIONS}}", sections)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(doc)
    size = os.path.getsize(out_path)
    print("wrote %s — %d screens, %.1f MB (cap 16 MB)"
          % (out_path, n, size / 1048576))
    if size > CAP_BYTES:
        print("WARNING: over the 16 MB Artifact cap; lower --width", file=sys.stderr)


TEMPLATE = r"""<title>{{TITLE}}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
:root{--ground:#F4F5F7;--surface:#FFF;--surface-alt:#EBEDF1;--line:#D6DAE1;--ink:#14171C;
--ink-soft:#5B6472;--ink-faint:#8C95A3;--accent:#B4741A;--pass:#2F7D57;--pass-soft:#DCEFE4;
--flag:#B4402C;--flag-soft:#F8DED8;--warn:#8A6410;--warn-soft:#FBEFD4;
--shadow:0 1px 2px rgba(20,23,28,.06),0 8px 24px rgba(20,23,28,.07);--radius:10px;
--step--1:.78rem;--step-0:.95rem;--step-1:1.15rem;}
@media(prefers-color-scheme:dark){:root:not([data-theme="light"]){--ground:#14171C;--surface:#1C2027;
--surface-alt:#252A33;--line:#333A45;--ink:#E9ECF1;--ink-soft:#A0A9B6;--ink-faint:#6E7887;
--accent:#E8A33D;--pass:#5FBE8C;--pass-soft:#1B2E24;--flag:#E8735C;--flag-soft:#33201C;
--warn:#E0B457;--warn-soft:#33290F;--shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px rgba(0,0,0,.35);}}
:root[data-theme="dark"]{--ground:#14171C;--surface:#1C2027;--surface-alt:#252A33;--line:#333A45;
--ink:#E9ECF1;--ink-soft:#A0A9B6;--ink-faint:#6E7887;--accent:#E8A33D;--pass:#5FBE8C;
--pass-soft:#1B2E24;--flag:#E8735C;--flag-soft:#33201C;--warn:#E0B457;--warn-soft:#33290F;
--shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px rgba(0,0,0,.35);}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;
font-size:var(--step-0);line-height:1.55;-webkit-font-smoothing:antialiased}
.mono{font-family:"IBM Plex Mono",ui-monospace,Menlo,monospace}
.bar{position:sticky;top:0;z-index:20;background:color-mix(in srgb,var(--ground) 88%,transparent);
backdrop-filter:blur(12px);border-bottom:1px solid var(--line);padding:.7rem 1rem;display:flex;
align-items:center;gap:.75rem}
.bar h1{margin:0;font-size:var(--step-0);font-weight:600;letter-spacing:-.01em;white-space:nowrap}
.build{font-size:var(--step--1);color:var(--ink-faint);white-space:nowrap}
.spacer{flex:1}
.count{font-size:var(--step--1);color:var(--ink-soft);font-variant-numeric:tabular-nums;white-space:nowrap}
.track{height:3px;background:var(--surface-alt);border-radius:2px;overflow:hidden;width:56px;flex:none}
.track>i{display:block;height:100%;width:0;background:var(--accent);transition:width .25s ease}
main{padding:1rem 1rem 4rem;max-width:1180px;margin:0 auto}
.group{margin-bottom:2.25rem}
.group>h2{margin:0 0 .2rem;font-size:var(--step--1);font-weight:500;text-transform:uppercase;
letter-spacing:.1em;color:var(--ink-faint);font-family:"IBM Plex Mono",ui-monospace,monospace}
.group>.rule{height:1px;background:var(--line);margin-bottom:1rem}
.grid{display:grid;gap:1rem;grid-template-columns:1fr}
@media(min-width:760px){.grid{grid-template-columns:1fr 1fr}}
.card{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);
box-shadow:var(--shadow);overflow:hidden;display:flex;flex-direction:column;
border-left:3px solid transparent;transition:border-left-color .18s ease}
.card[data-verdict="pass"]{border-left-color:var(--pass)}
.card[data-verdict="flag"]{border-left-color:var(--flag)}
/* One fixed viewport per thumbnail. Without it a 1206x2622 phone shot renders
   six times taller than a 3840x2098 Mac window in the same grid, and the wide
   one becomes unreadable. contain + a neutral mat keeps both legible. */
.shot{display:flex;align-items:center;justify-content:center;width:100%;
height:clamp(260px,42vh,380px);border:0;padding:0;background:var(--surface-alt);
cursor:zoom-in;overflow:hidden}
.shot img{max-width:100%;max-height:100%;width:auto;height:auto;display:block;
object-fit:contain}
.shot:focus-visible{outline:3px solid var(--accent);outline-offset:-3px}
.body{padding:.85rem .95rem 1rem;display:flex;flex-direction:column;gap:.55rem}
.name{margin:0;font-size:var(--step-1);font-weight:600;letter-spacing:-.01em;
display:flex;align-items:center;gap:.5rem;flex-wrap:wrap}
.warn{font-size:var(--step--1);font-weight:500;color:var(--warn);background:var(--warn-soft);
padding:.1rem .45rem;border-radius:999px;font-family:"IBM Plex Mono",monospace}
.meta{font-size:var(--step--1);color:var(--ink-faint)}
.changed{margin:0;color:var(--ink-soft)}
.actions{display:flex;gap:.45rem;align-items:center;margin-top:.2rem}
button.verdict{font:inherit;font-size:var(--step--1);font-weight:500;padding:.38rem .7rem;
border-radius:999px;cursor:pointer;border:1px solid var(--line);background:var(--surface);
color:var(--ink-soft);transition:background .15s,color .15s,border-color .15s}
button.verdict:hover{border-color:var(--ink-faint);color:var(--ink)}
button.verdict:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
.card[data-verdict="pass"] .verdict[data-v="pass"]{background:var(--pass-soft);color:var(--pass);border-color:var(--pass)}
.card[data-verdict="flag"] .verdict[data-v="flag"]{background:var(--flag-soft);color:var(--flag);border-color:var(--flag)}
.note{margin-left:auto;font-size:var(--step--1);color:var(--ink-faint);font-family:"IBM Plex Mono",monospace}
dialog.lb{border:0;padding:0;background:transparent;max-width:96vw;max-height:94vh}
dialog.lb::backdrop{background:rgba(10,12,15,.85)}
dialog.lb img{display:block;max-width:96vw;max-height:94vh;width:auto;height:auto;border-radius:var(--radius)}
@media(prefers-reduced-motion:reduce){*{transition:none!important}}
</style>
<div class="bar">
  <h1>{{TITLE}}</h1>
  <span class="build mono">{{BUILD}}</span>
  <span class="spacer"></span>
  <span class="count mono" id="count">0/{{COUNT}} judged</span>
  <span class="track"><i id="fill"></i></span>
</div>
<main>{{SECTIONS}}</main>
<dialog class="lb" id="lb"><img id="lb-img" alt=""></dialog>
<script>
const lb=document.getElementById('lb'),lbImg=document.getElementById('lb-img');
document.querySelectorAll('.shot').forEach(b=>b.addEventListener('click',()=>{
  lbImg.src=b.querySelector('img').src;lb.showModal();}));
lb.addEventListener('click',()=>lb.close());
document.querySelectorAll('.card').forEach(card=>{
  card.querySelectorAll('.verdict').forEach(b=>b.addEventListener('click',()=>{
    const v=b.dataset.v;
    card.dataset.verdict=card.dataset.verdict===v?'':v;
    card.querySelector('.note').textContent=
      card.dataset.verdict==='pass'?'shipping':card.dataset.verdict==='flag'?'needs work':'';
    tally();}));});
function tally(){const cs=[...document.querySelectorAll('.card')],
  d=cs.filter(c=>c.dataset.verdict).length;
  document.getElementById('count').textContent=`${d}/${cs.length} judged`;
  document.getElementById('fill').style.width=(d/cs.length*100)+'%';}
tally();
</script>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", nargs="?", help="JSON manifest, or omit with --from-dir")
    ap.add_argument("out")
    ap.add_argument("--from-dir", help="build entries from every image in DIR")
    ap.add_argument("--title", default="Screen Review")
    ap.add_argument("--build", default="")
    ap.add_argument("--width", type=int, default=900,
                    help="long-edge px for portrait shots; landscape gets 2x")
    ap.add_argument("--auto", action="store_true",
                    help="unattended run; refuses unless the gallery flag file exists")
    a = ap.parse_args()

    # Unattended generation only happens when the user has explicitly armed it.
    # Enforced here rather than left to the caller's discretion, so "full auto"
    # is a state the user owns, not a promise the agent makes.
    if a.auto:
        flag = os.environ.get("CC_GALLERY_FLAG",
                              os.path.expanduser("~/.claude/gallery-enabled"))
        if not os.path.exists(flag):
            print("cc-gallery: --auto refused, %s does not exist.\n"
                  "  Full-auto galleries are off. Turn them on with:\n"
                  "    cc-gallery-toggle on" % flag, file=sys.stderr)
            sys.exit(3)

    if a.from_dir:
        names = sorted(f for f in os.listdir(a.from_dir)
                       if f.lower().endswith((".png", ".jpg", ".jpeg")))
        entries = [{"path": os.path.join(a.from_dir, f),
                    "name": os.path.splitext(f)[0].rsplit("-", 2)[0],
                    "meta": os.path.splitext(f)[0]} for f in names]
    else:
        if not a.manifest:
            ap.error("give a manifest or --from-dir")
        with open(a.manifest, encoding="utf-8") as fh:
            entries = json.load(fh)

    build(entries, a.out, a.title, a.build, a.width)


if __name__ == "__main__":
    main()
