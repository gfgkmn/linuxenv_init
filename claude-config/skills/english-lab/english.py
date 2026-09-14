#!/usr/bin/env python3
"""english-lab — everything the loop needs, in one command.

    english.py update [--rebuild] [--quiet]   pull new material, measure, age the queue
    english.py drill  [--brief] [--json]      material for today
    english.py add <item> [--kind …] [--note …] [--source …]
    english.py drop <item>
    english.py list
    english.py report                         weekly markdown into the notes vault
    english.py range                          range table, year by year
    english.py eudic pull|cross|push          wordbook bridge

The division of labour is the whole design. This script does the two things a
model cannot do for itself — remember what was taught across sessions, and
count across years of text. It holds no word list and makes no teaching
decision; an earlier version did, from a frequency table, and offered `purely`
as a replacement for `just` in a sentence where `just` meant *merely* — two
words a table lists as synonyms and a reader never confuses. Sense is not
countable. Mining the user's own corpus for targets is capped by definition
too: it can only reflect back the range already in it.

Nothing has to be logged by hand, because the corpus IS the log. An item taught
last week is checked by searching this week's messages for it, and practice
answers arrive on their own when they are spoken through the dictation tool.

Personal findings are never written into this repository — only into the state
directory below.
"""
import argparse
import collections
import datetime
import difflib
import glob
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rules

HOME = os.path.expanduser("~")
STATE = os.environ.get("ENGLISH_LAB_HOME", f"{HOME}/.claude/english")
ECHOES = os.environ.get("ENGLISH_LAB_ARCHIVE", f"{HOME}/Documents/ChatgptHistory/Echoes-ALL")
SESSIONS = f"{HOME}/.claude/projects"
DICT_DB = f"{HOME}/Library/Application Support/Typeless/typeless.db"
RECORDINGS = f"{HOME}/Library/Application Support/Typeless/Recordings"
VAULT = os.environ.get("ENGLISH_LAB_VAULT",
    f"{HOME}/Library/Mobile Documents/iCloud~md~obsidian/Documents/English Lab")

# Verbatim, not readable. A/B'd against a clean-text model on identical audio:
# this one returns half again as many words, because the other deletes the
# fillers, repetitions and repairs — and those ARE the fluency measurement.
# The clean-text model remains the right choice for the user's own dictation,
# where a tidy transcript is exactly what is wanted. Opposite jobs.
ASR_MODEL = os.environ.get("ENGLISH_LAB_ASR", "mlx-community/parakeet-tdt-0.6b-v3")

EUDIC_API = "https://api.frdic.com/api/open/v1/studylist"

# Intervals advance on EVIDENCE, never on the calendar. An earlier version aged
# every item that came due, so something never once produced still drifted out
# to a 35-day gap and quietly vanished — exactly backwards.
SRS_DAYS = [1, 3, 7, 16, 35, 70]
MISS_GAP = 2      # days until the next attempt when it did not land
STALL_AT = 4      # silent prompts before the ITEM is the suspect, not the memory


# ------------------------------------------------------------- state io ----

def state_path(name):
    os.makedirs(STATE, exist_ok=True)
    return os.path.join(STATE, name)


def load_json(name, default):
    try:
        return json.load(open(state_path(name), encoding="utf-8"))
    except Exception:
        return default


def save_json(name, obj):
    p = state_path(name)
    json.dump(obj, open(p + ".tmp", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    os.replace(p + ".tmp", p)


def load_lines(name):
    out = []
    if os.path.exists(state_path(name)):
        for line in open(state_path(name), encoding="utf-8"):
            try:
                out.append(json.loads(line))
            except Exception:
                pass
    return out


def append_line(name, obj):
    with open(state_path(name), "a", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, ensure_ascii=False) + "\n")


def write_lines(name, rows):
    p = state_path(name)
    with open(p + ".tmp", "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.replace(p + ".tmp", p)


def today():
    return datetime.date.today().isoformat()


def norm(s):
    return re.sub(r'\s+', ' ', s or '').strip().lower()


# ------------------------------------------------------------- sources ----

def dictation_rows():
    """(id, rewritten_text, created_at, audio_path) from the dictation tool.

    Copied before reading: the app holds the live database open, and this must
    never write to it. The copy is removed immediately — it is the user's whole
    dictation history and has no business lingering on disk.
    """
    if not os.path.exists(DICT_DB):
        return []
    tmp = state_path("_dict.db")
    shutil.copy(DICT_DB, tmp)
    rows = []
    try:
        db = sqlite3.connect(tmp)
        for table in ("history_v2", "history"):
            try:
                rows += list(db.execute(
                    f"select id, refined_text, created_at, audio_local_path "
                    f"from {table} where refined_text is not null"))
            except sqlite3.Error:
                pass
        db.close()
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return rows


def rewritten_texts():
    return {norm(t) for _, t, _, _ in dictation_rows() if t and len(t) > 40}


def scan_sessions(since, skip):
    out = []
    for f in glob.glob(f"{SESSIONS}/*/*.jsonl"):
        for line in open(f, encoding="utf-8", errors="ignore"):
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("type") != "user":
                continue
            date = (o.get("timestamp") or "")[:10]
            if not date or date <= since:
                continue
            c = (o.get("message") or {}).get("content")
            if isinstance(c, list):
                parts = [b.get("text", "") for b in c
                         if isinstance(b, dict) and b.get("type") == "text"]
                c = "\n".join(parts) if parts else None
            if not isinstance(c, str):
                continue
            t = rules.keep(c, date, skip)
            if t:
                out.append({"date": date, "source": "cli", "year": date[:4],
                            "words": len(rules.WORD.findall(t)), "text": t})
    return out


def scan_archive(since, skip):
    out = []
    for f in glob.glob(ECHOES + "/*.json"):
        base = os.path.basename(f)
        m = re.search(r'(\d{4})(\d{2})(\d{2})', base)
        date = f"{m.group(1)}-{m.group(2)}-{m.group(3)}" if m else "0000-00-00"
        if date <= since:
            continue
        try:
            d = json.load(open(f, encoding="utf-8", errors="ignore"))
        except Exception:
            continue
        msgs = d.get("messages") or []
        if isinstance(msgs, dict):
            msgs = list(msgs.values())
        src = base.split()[0].lower()
        for x in msgs:
            if x.get("role") != "user" or not isinstance(x.get("content"), str):
                continue
            t = rules.keep(x["content"], date, skip)
            if t:
                out.append({"date": date, "source": src, "year": date[:4],
                            "words": len(rules.WORD.findall(t)), "text": t})
    return out


def transcribe(ogg, timeout=300):
    """Verbatim transcript of one recording. Fidelity beats word error rate
    here: the hesitations and slips ARE the data, so a model that tidies them
    away has deleted the measurement."""
    base = state_path(f"_tx{os.getpid()}")
    wav, txt = base + ".wav", base + ".txt"
    try:
        subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", ogg,
                        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav],
                       capture_output=True, timeout=120, check=True)
        subprocess.run(["parakeet-mlx", wav, "--model", ASR_MODEL,
                        "--output-format", "txt", "--output-dir", os.path.dirname(base)],
                       capture_output=True, text=True, timeout=timeout)
        if not os.path.exists(txt):
            return ""
        return re.sub(r'\s+', ' ',
                      open(txt, encoding="utf-8", errors="ignore").read()).strip()
    except Exception:
        return ""
    finally:
        for f in (wav, txt):
            if os.path.exists(f):
                os.remove(f)


def english_recordings(since):
    out = []
    for rid, text, created, path in dictation_rows():
        if not text or rules.CJK.search(text):
            continue
        if len(rules.WORD.findall(text)) < 8:
            continue
        date = (created or "")[:10]
        if not date or date <= since:
            continue
        ogg = path if (path and os.path.exists(path)) \
            else os.path.join(RECORDINGS, f"{rid}.ogg")
        if os.path.exists(ogg):
            out.append({"id": rid, "date": date, "ogg": ogg})
    return out


# -------------------------------------------------------------- update ----

def cmd_update(a):
    def log(*x):
        if not a.quiet:
            print(*x, flush=True)

    cursor = load_json("cursor.json", {})
    log("english-lab" + (" (rebuild)" if a.rebuild else ""))

    since = "0000-00-00" if a.rebuild else cursor.get("corpus", "0000-00-00")
    skip = rewritten_texts()
    fresh = scan_sessions(since, skip) + scan_archive(since, skip)
    if a.rebuild:
        write_lines("corpus.jsonl", fresh)
    else:
        seen = {norm(r["text"]) for r in load_lines("corpus.jsonl")}
        fresh = [r for r in fresh if norm(r["text"]) not in seen]
        for r in fresh:
            append_line("corpus.jsonl", r)
    if fresh:
        cursor["corpus"] = max(r["date"] for r in fresh)
    log(f"  corpus  +{len(fresh)}")

    since = "0000-00-00" if a.rebuild else cursor.get("speech", "0000-00-00")
    done = set() if a.rebuild else {p["id"] for p in load_lines("speech.jsonl")}
    todo = [r for r in english_recordings(since) if r["id"] not in done]
    if a.rebuild:
        write_lines("speech.jsonl", [])
    n = 0
    for r in todo:
        raw = transcribe(r["ogg"])
        if raw:
            append_line("speech.jsonl", {"id": r["id"], "date": r["date"], "text": raw})
            n += 1
    if todo:
        cursor["speech"] = max(r["date"] for r in todo)
    log(f"  speech  +{n}")

    corpus = load_lines("corpus.jsonl")
    if not corpus:
        log("  no corpus — run with --rebuild")
        return 1

    cut = (datetime.date.today() - datetime.timedelta(days=120)).isoformat()
    written = [r["text"] for r in corpus if r["date"] >= cut] or [r["text"] for r in corpus]
    spoken = [p["text"] for p in load_lines("speech.jsonl") if p["date"] >= cut]

    m = {"week": _isoweek(), "date": today(), "written": rules.measure(written)}
    if spoken:
        m["spoken"] = rules.measure(spoken)
        f = rules.fluency(spoken)
        if f:
            m["fluency"] = f

    hist = load_lines("metrics.jsonl")
    if hist and hist[-1].get("week") == m["week"]:
        hist[-1] = m
        write_lines("metrics.jsonl", hist)
    else:
        append_line("metrics.jsonl", m)

    queue, graduated, stalled = age_queue()
    cursor["last_run"] = today()
    save_json("cursor.json", cursor)

    w = m["written"]
    log(f"  range   {w['structures_live']}/{w['structures_total']} structures live · "
        f"crutches {w['crutch_per_1k']}/1k · openings {w['opening_top5_share']}")
    if m.get("fluency"):
        fl = m["fluency"]
        log(f"  fluency fillers {fl['filler_per_1k']}/1k · repeats {fl['repeat_per_1k']} · "
            f"repairs {fl['repair_per_1k']}")
    log(f"  queue   {len(queue)} active, {graduated} graduated" +
        (f", {stalled} stalled" if stalled else ""))
    return 0


def _isoweek():
    y, w, _ = datetime.date.today().isocalendar()
    return f"{y}-W{w:02d}"


def age_queue():
    """Graduate on evidence, reschedule on evidence, and admit when an item is
    simply a bad pick.

    Graduation needs 3+ unprompted uses across 2+ distinct weeks: three uses in
    one day is short-term memory, not acquisition. Both channels count, because
    the question is whether the thing entered production at all.
    """
    queue = load_lines("queue.jsonl")
    if not queue:
        return queue, 0, 0
    material = load_lines("corpus.jsonl") + load_lines("speech.jsonl")
    now = today()
    still, graduated, stalled = [], 0, 0

    for q in queue:
        pat = re.compile(r"\b" + re.escape(q["item"]) + r"\b", re.I)
        hits, weeks = 0, set()
        for r in material:
            if r["date"] < q["added"]:
                continue
            found = len(pat.findall(r["text"]))
            if found:
                hits += found
                y, w, _ = datetime.date.fromisoformat(r["date"]).isocalendar()
                weeks.add(f"{y}-{w}")
        q["hits"], q["weeks"] = hits, len(weeks)

        if hits >= 3 and len(weeks) >= 2:
            append_line("graduated.jsonl",
                        {**{k: q[k] for k in ("item", "kind", "note", "added")},
                         "graduated": now, "hits": hits, "weeks": len(weeks)})
            graduated += 1
            continue

        if q.get("due", now) <= now:
            if hits > q.get("last_hits", 0):
                # Real use beats any drill, so the schedule rewards it and
                # stands back.
                q["stage"] = min(q.get("stage", 0) + 1, len(SRS_DAYS) - 1)
                q["misses"] = 0
                gap = SRS_DAYS[q["stage"]]
            else:
                q["misses"] = q.get("misses", 0) + 1
                gap = MISS_GAP
                if q["misses"] >= STALL_AT:
                    # Four prompts and nothing in production is rarely a memory
                    # failure. It usually means the item was a poor choice —
                    # too abstract, or not how this person talks.
                    q["stalled"] = True
                    gap = SRS_DAYS[min(q.get("stage", 0) + 1, len(SRS_DAYS) - 1)]
            q["last_hits"] = hits
            q["due"] = (datetime.date.fromisoformat(now)
                        + datetime.timedelta(days=gap)).isoformat()
        if q.get("stalled"):
            stalled += 1
        still.append(q)

    write_lines("queue.jsonl", still)
    return still, graduated, stalled


# --------------------------------------------------------------- drill ----

def _sentences(text, date, mode, lo=12, hi=45):
    out = []
    for s in re.split(r'(?<=[.!?])\s+', text):
        s = s.strip()
        n = len(re.findall(r"[A-Za-z]+", s))
        if (lo <= n <= hi and s[:1].isalpha()
                and not rules.PATHY.search(s) and not rules.PASTED.search(s)):
            out.append({"text": s, "date": date, "mode": mode})
    return out


def cmd_drill(a):
    random.seed(int(datetime.date.today().strftime("%Y%m%d")))
    cut = (datetime.date.today() - datetime.timedelta(days=120)).isoformat()

    typed, spoken = [], []
    for r in load_lines("corpus.jsonl"):
        if r["date"] >= cut:
            typed += _sentences(r["text"], r["date"], "typed")
    for p in load_lines("speech.jsonl"):
        if p["date"] >= cut:
            spoken += _sentences(p["text"], p["date"], "spoken")
    random.shuffle(typed)
    random.shuffle(spoken)

    n = 2 if a.brief else 6
    want_spoken = max(1, n // 2)      # speech is the weaker channel
    picks = (spoken[:want_spoken] + typed[:n - want_spoken])[:n]
    random.shuffle(picks)

    queue = load_lines("queue.jsonl")
    due = [q for q in queue if q.get("due", today()) <= today()]

    if a.json:
        print(json.dumps({"utterances": picks, "due": due,
                          "hints": eudic_cross(8)}, ensure_ascii=False, indent=1))
        return 0
    if not picks:
        print("No material yet. Run: english.py update --rebuild")
        return 1

    print("\n\033[1m你最近说过 / 写过的话\033[0m")
    for i, u in enumerate(picks, 1):
        tag = "说" if u["mode"] == "spoken" else "写"
        print(f"\n  {i}. \033[2m[{tag} · {u['date']}]\033[0m {u['text']}")

    hints = eudic_cross(8)
    if hints:
        print("\n\033[1m可选素材 — 你查过、反复读到、但从没说出口\033[0m")
        print("  \033[2m只在它恰好能改进上面某句话时才用;不要为了用而用。\033[0m")
        print("  " + " · ".join(f"\033[36m{h['word']}\033[0m\033[2m({h['read']})\033[0m"
                                for h in hints))

    if due:
        landed = [q for q in due if q.get("hits", 0) > q.get("last_hits", 0)]
        stalled = [q for q in due if q.get("stalled")]
        needs = [q for q in due if q not in landed and q not in stalled]

        if landed:
            print(f"\n\033[1m已经用上了({len(landed)} 项,不用再练)\033[0m")
            for q in landed:
                print(f"  ✓ \033[36m{q['item']}\033[0m  \033[2m自发用过 "
                      f"{q['hits']} 次 / {q.get('weeks', 0)} 周\033[0m")
        if needs:
            print(f"\n\033[1m复习 — 出声造句({len(needs)} 项)\033[0m")
            print("  教过但还没在你的真实产出里出现。现在用它说一句关于你手头的事。\n")
            for q in needs:
                miss = q.get("misses", 0)
                mark = f"  \033[33m(第 {miss + 1} 次提示)\033[0m" if miss else ""
                print(f"  · \033[36m{q['item']}\033[0m{mark}")
                if q.get("note"):
                    print(f"    \033[2m{q['note']}\033[0m")
                if q.get("source"):
                    print(f"    \033[2m当初来自:「{q['source'][:90]}」\033[0m")
        if stalled:
            print(f"\n\033[1m\033[33m卡住了({len(stalled)} 项)—— 换个教法\033[0m")
            print("  提示四次仍未进入产出。多半是这一项选错了,不是记不住。\n")
            for q in stalled:
                print(f"  · \033[36m{q['item']}\033[0m  \033[2m{q.get('note', '')}\033[0m")
    print()
    return 0


# --------------------------------------------------------------- queue ----

def cmd_add(a):
    queue = load_lines("queue.jsonl")
    known = {q["item"].lower() for q in queue}
    known |= {g["item"].lower() for g in load_lines("graduated.jsonl")}
    if a.item.lower() in known:
        print(f"already tracked or graduated: {a.item}")
        return 0
    queue.append({"item": a.item, "kind": a.kind, "note": a.note, "source": a.source,
                  "added": today(), "due": today(), "stage": 0,
                  "hits": 0, "weeks": 0, "last_hits": 0, "misses": 0})
    write_lines("queue.jsonl", queue)
    print(f"tracking: {a.item}  ({a.kind})")
    return 0


def cmd_drop(a):
    queue = load_lines("queue.jsonl")
    left = [q for q in queue if q["item"].lower() != a.item.lower()]
    write_lines("queue.jsonl", left)
    print(f"dropped {len(queue) - len(left)}: {a.item}")
    return 0


def cmd_list(_a):
    queue = load_lines("queue.jsonl")
    if not queue:
        print("(queue empty)")
    for q in sorted(queue, key=lambda x: x.get("due", "")):
        flag = " STALLED" if q.get("stalled") else ""
        print(f"  {q['due']}  [{q['kind']:<11}] {q['item']:<22} "
              f"hits={q.get('hits', 0)}/{q.get('weeks', 0)}w{flag}  {q.get('note', '')[:46]}")
    grads = load_lines("graduated.jsonl")
    if grads:
        print(f"\n  graduated: {len(grads)} — " + ", ".join(g["item"] for g in grads[-8:]))
    return 0


# -------------------------------------------------------------- report ----

def _arrow(cur, prev, higher_is_better=True):
    if prev is None or cur is None:
        return ""
    if abs(cur - prev) < 1e-9:
        return " →"
    good = (cur > prev) if higher_is_better else (cur < prev)
    return f" {'↑' if cur > prev else '↓'}{' ✅' if good else ' ⚠️'}"


def cmd_report(_a):
    hist = load_lines("metrics.jsonl")
    if not hist:
        print("no metrics yet — run update first")
        return 1
    m, prev = hist[-1], (hist[-2] if len(hist) > 1 else None)
    w = m["written"]
    pw = (prev or {}).get("written") or {}
    queue = load_lines("queue.jsonl")
    week_ago = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
    recent = [g for g in load_lines("graduated.jsonl") if g.get("graduated", "") >= week_ago]

    L = [f"# English Lab — {m['week']}\n",
         f"*{m['date']}。数字从你自己的产出里重算，不靠自评。*\n",
         "## 指标\n", "| 指标 | 本期 | 变化 |", "|---|---|---|",
         f"| 在用的句法结构 | **{w['structures_live']} / {w['structures_total']}** |"
         f"{_arrow(w['structures_live'], pw.get('structures_live'))} |",
         f"| 笼统词 / 千词 | **{w['crutch_per_1k']}** |"
         f"{_arrow(w['crutch_per_1k'], pw.get('crutch_per_1k'), False)} |",
         f"| 句首前5集中度 | **{w['opening_top5_share']}** |"
         f"{_arrow(w['opening_top5_share'], pw.get('opening_top5_share'), False)} |",
         f"| 本周毕业 | **{len(recent)}** | 队列中 {len(queue)} |\n"]

    if m.get("fluency"):
        f, pf = m["fluency"], (prev or {}).get("fluency") or {}
        L += ["## 流利度（逐字转写）\n",
              "*填充词、重复、自我修正是流利度的直接证据。会把文本"
              "顺干净的模型会删光它们，所以这几项只有用逐字转写才存在。*\n",
              "| 指标 | 本期 | 变化 | 读法 |", "|---|---|---|---|",
              f"| 填充词 / 千词 | **{f['filler_per_1k']}** |"
              f"{_arrow(f['filler_per_1k'], pf.get('filler_per_1k'), False)} | 越低越流利 |",
              f"| 重复 / 千词 | **{f['repeat_per_1k']}** |"
              f"{_arrow(f['repeat_per_1k'], pf.get('repeat_per_1k'), False)} | 卡顿时的拖延 |",
              f"| 自我修正 / 千词 | **{f['repair_per_1k']}** |"
              f"{_arrow(f['repair_per_1k'], pf.get('repair_per_1k'), False)} |"
              f" **不是错误** —— 规则你懂，只是实时调不出 |", ""]

    L += ["## 句法结构可用性\n",
          "*近零的不是「用错」，是「根本不调用」——只能靠强制产出练。*\n",
          "| 结构 | 每千词 |", "|---|---|"]
    for _, v in sorted(w["structures"].items(), key=lambda x: -x[1]["per_1k"]):
        L.append(f"| {v['label']} | {v['per_1k']}"
                 f"{'' if v['per_1k'] >= 0.1 else '  ⚠️ 未在用'} |")
    L.append("")

    if w.get("stiff"):
        L += ["## 语域偏硬的词（书面腔）\n"]
        for k, n in sorted(w["stiff"].items(), key=lambda x: -x[1]):
            L.append(f"- `{k}` × {n} → {rules.STIFF.get(k, '')}")
        L.append("")

    if queue:
        L += ["## 在练\n", "| 项 | 类型 | 已自发使用 | 说明 |", "|---|---|---|---|"]
        for q in sorted(queue, key=lambda x: -x.get("hits", 0)):
            L.append(f"| **{q['item']}** | {q.get('kind', '')} |"
                     f" {q.get('hits', 0)} 次 / {q.get('weeks', 0)} 周 | {q.get('note', '')} |")
        L.append("")

    if recent:
        L += ["## 本周毕业\n"]
        L += [f"- **{g['item']}** — {g['hits']} 次，跨 {g['weeks']} 周" for g in recent]
        L.append("")

    L += ["## 本周语音练习\n", "语音模式 15 分钟。规则：\n",
          "1. 至少用上队列里的 3 项。",
          "2. 强制使用一个当前近零的结构（见上表 ⚠️）。",
          "3. 话题取自你本周真实做过的事。\n",
          "> 发音这一项文字语料看不见，只能在这 15 分钟里当场判断。\n"]

    os.makedirs(VAULT, exist_ok=True)
    path = os.path.join(VAULT, f"{m['week']}.md")
    open(path, "w", encoding="utf-8").write("\n".join(L))
    print(f"wrote {path}")
    return 0


def cmd_range(_a):
    by = collections.defaultdict(list)
    for r in load_lines("corpus.jsonl"):
        by[r["year"]].append(r["text"])
    years = sorted(by)
    if not years:
        print("no corpus")
        return 1
    res = {y: rules.measure(by[y]) for y in years}
    head = f"{'structure':<36}" + "".join(f"{y:>9}" for y in years)
    print(head, "-" * len(head), sep="\n")
    for key, (label, _) in rules.STRUCTURES.items():
        print(f"{label:<36}" + "".join(f"{res[y]['structures'][key]['per_1k']:>9.2f}"
                                       for y in years))
    print("-" * len(head))
    for k, name in (("structures_live", "structures live"),
                    ("crutch_per_1k", "crutches /1k"),
                    ("opening_top5_share", "opening top-5 share")):
        print(f"{name:<36}" + "".join(f"{res[y][k]:>9}" for y in years))
    return 0


# --------------------------------------------------------------- eudic ----
# The wordbook records what was looked up WHILE READING — input-side data. The
# bottleneck here is output-side, so importing it wholesale would bury the queue
# under words several rungs below the ones already failing to activate. Only the
# intersection earns a place: looked up, AND read often, AND never produced.

def eudic_headers():
    cfg = load_json("config.json", {})
    tok = cfg.get("TOKEN") or cfg.get("EUDIC_TOKEN") or ""
    if not tok:
        print('No EuDict token. Put {"TOKEN": "NIS …"} in '
              f'{state_path("config.json")} — from '
              "https://my.eudic.net/OpenAPI/Authorization", file=sys.stderr)
        sys.exit(2)
    return {"Authorization": tok if tok.startswith("NIS") else "NIS " + tok,
            "Content-Type": "application/json"}


def eudic_call(path, method="GET", body=None):
    req = urllib.request.Request(EUDIC_API + path, headers=eudic_headers(),
                                 method=method,
                                 data=json.dumps(body).encode() if body else None)
    with urllib.request.urlopen(req, timeout=30) as f:
        raw = f.read().decode()
    return json.loads(raw) if raw.strip() else {}


def reading_counts():
    cached = load_json("reading.json", None)
    if cached:
        return collections.Counter(cached)
    c = collections.Counter()
    for f in glob.glob(ECHOES + "/*.json"):
        try:
            d = json.load(open(f, encoding="utf-8", errors="ignore"))
        except Exception:
            continue
        msgs = d.get("messages") or []
        if isinstance(msgs, dict):
            msgs = list(msgs.values())
        for x in msgs:
            if x.get("role") == "assistant" and isinstance(x.get("content"), str):
                c.update(rules.LOWER.findall(x["content"].lower()))
    save_json("reading.json", dict(c))
    return c


# Domain nouns are not an expression gap; they would crowd out the words that
# actually widen range.
TECH_NOUNS = set("""networks network formatting rag abs quad pages ram cpu gpu gpus
api apis json yaml http https url urls repo repos commit branch merge cache token
tokens prompt prompts model models dataset datasets tensor vector vectors embed
embedding embeddings runtime kernel kernels buffer buffers thread threads proxy
server client daemon binary compiler linker parser frontend backend database
schema index query queries latency throughput simulator container containers
cluster clusters""".split())


def eudic_cross(limit=25):
    looked_up = {(w.get("word") or "").strip().lower()
                 for w in load_json("eudic_words.json", [])}
    looked_up = {w for w in looked_up if w and " " not in w and w.isalpha()}
    if not looked_up:
        return []
    produced = collections.Counter()
    for r in load_lines("corpus.jsonl"):
        produced.update(rules.LOWER.findall(r["text"].lower()))
    for p in load_lines("speech.jsonl"):
        produced.update(rules.LOWER.findall(p["text"].lower()))
    read = reading_counts()
    busy = {q["item"].lower() for q in load_lines("queue.jsonl")}
    busy |= {g["item"].lower() for g in load_lines("graduated.jsonl")}

    out = []
    for w in looked_up:
        if w in TECH_NOUNS or w in busy or produced.get(w, 0) >= 3:
            continue
        if read.get(w, 0) < 30:     # comprehension edge, not an expression gap
            continue
        out.append({"word": w, "read": read[w]})
    out.sort(key=lambda x: -x["read"])
    return out[:limit]


def cmd_eudic(a):
    if a.action == "pull":
        books = eudic_call("/category?language=en").get("data") or []
        book = a.book if a.book is not None else (books[0]["id"] if books else 0)
        words, page = [], 0
        while page < 60:
            batch = eudic_call(
                f"/words/{book}?language=en&page={page}&page_size=100").get("data") or []
            if not batch:
                break
            words += batch
            if len(batch) < 100:
                break
            page += 1
            time.sleep(0.2)
        save_json("eudic_words.json", words)
        print(f"pulled {len(words)} words from book {book}")
    elif a.action == "cross":
        rows = eudic_cross(a.limit)
        if not rows:
            print("(nothing — run `eudic pull` first)")
        for r in rows:
            print(f"  {r['word']:<18} read {r['read']:>4}x")
    elif a.action == "push":
        items = [q["item"] for q in load_lines("queue.jsonl")]
        if not items:
            print("queue empty")
            return 0
        books = eudic_call("/category?language=en").get("data") or []
        book = a.book if a.book is not None else (books[0]["id"] if books else 0)
        eudic_call("/words", "POST", {"id": book, "language": "en", "words": items})
        print(f"pushed {len(items)} into book {book}: {', '.join(items)}")
    return 0


# ----------------------------------------------------------------- cli ----

def main():
    p = argparse.ArgumentParser(prog="english.py", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    u = sub.add_parser("update", help="pull new material, measure, age the queue")
    u.add_argument("--rebuild", action="store_true")
    u.add_argument("--quiet", action="store_true")
    u.set_defaults(fn=cmd_update)

    d = sub.add_parser("drill", help="material for today")
    d.add_argument("--brief", action="store_true", help="two utterances, for the hook")
    d.add_argument("--json", action="store_true")
    d.set_defaults(fn=cmd_drill)

    a_ = sub.add_parser("add", help="start tracking something you just taught")
    a_.add_argument("item")
    a_.add_argument("--kind", default="lexical",
                    choices=["lexical", "structure", "register", "collocation", "habit"])
    a_.add_argument("--note", default="", help="one line, Chinese — why it matters")
    a_.add_argument("--source", default="", help="the sentence of theirs it came from")
    a_.set_defaults(fn=cmd_add)

    dr = sub.add_parser("drop", help="stop tracking a bad pick")
    dr.add_argument("item")
    dr.set_defaults(fn=cmd_drop)

    sub.add_parser("list", help="show the queue").set_defaults(fn=cmd_list)
    sub.add_parser("report", help="weekly markdown into the vault").set_defaults(fn=cmd_report)
    sub.add_parser("range", help="range table, year by year").set_defaults(fn=cmd_range)

    e = sub.add_parser("eudic", help="wordbook bridge")
    e.add_argument("action", choices=["pull", "cross", "push"])
    e.add_argument("--book", type=int, default=None)
    e.add_argument("--limit", type=int, default=25)
    e.set_defaults(fn=cmd_eudic)

    args = p.parse_args()
    os.makedirs(STATE, exist_ok=True)
    try:
        return args.fn(args)
    except urllib.error.HTTPError as ex:
        print(f"EuDict API {ex.code}: {ex.reason}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
