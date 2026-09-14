#!/usr/bin/env python3
"""What gets measured, and why those things and not others.

Split out from the machinery because this is the part worth reading on its own:
it encodes a judgement about which differences in someone's English actually
matter, and that judgement is easy to get wrong.

The first version of this skill counted mistakes — missing plural -s, missing
articles, third-person agreement. Two things were wrong with that, and they are
the same mistake seen twice. Those patterns were chosen because a regular
expression could see them, and then their frequency was allowed to stand in for
their importance. But a listener does not downgrade "this setting exist"; they
downgrade "very good, very important, very strange". Morphology slips cost
nothing; a narrow repertoire costs everything.

So what follows measures RANGE. The failure mode that matters is silence — a
construction that never appears at all — and no error detector can see
something that was never said.

Nothing here is personal. Per-user findings live in the state directory, not in
this repository.
"""
import collections
import re

WORD = re.compile(r"[A-Za-z][A-Za-z'-]*")
LOWER = re.compile(r"[a-z][a-z'-]{2,}")
CJK = re.compile(r'[一-鿿]')


# --------------------------------------------------------------- corpus ----
# Which text can be trusted to be the user's own production.
#
# Dictation tools differ in how much they rewrite. One that only fixes typos
# leaves grammar, syntax and word choice untouched, so its output is still the
# speaker's. One that rewrites for style is useless here: it changes word choice
# too, and would flatter every measurement. TYPELESS_START is the date the
# rewriting tool came into use; everything before it is clean by default.
TYPELESS_START = "2026-03-14"

CODEY = re.compile(r'^\s*(def |class |import |from |function |const |let |var |'
                   r'<\?xml|\{|\[|\$ |#!/)', re.M)
PASTED = re.compile(r'\b[0-9A-F]{8}-[0-9A-F]{4}|\[[0-9A-F-]{12,}\]|\.framework\b|'
                    r'\b(dSYM|Traceback|at 0x[0-9a-f]+|warning:|error:)\b')
PATHY = re.compile(r'(/[A-Za-z0-9._~-]+){2,}|https?://|'
                   r'\.(png|jpg|json|py|swift|md)\b')
NOISE = ("<local-command", "<command-name>", "<system-reminder>",
         "Caveat: The messages below", "<cross-session-message",
         "[Request interrupted", "<task-notification>",
         "This session is being continued", "<persisted-output>")


def looks_polished(text):
    """True when a message was probably produced by the rewriting dictation
    tool rather than typed.

    Calibrated against messages confirmed to be that tool's output: they never
    contain a lone lowercase "i", capitalise almost every sentence, and always
    end in punctuation. Used ONE WAY ONLY — a hit means "possibly rewritten,
    drop it", never "definitely typed". Losing a carefully typed message costs
    a sample; letting rewritten prose into the statistics costs the whole
    measurement.
    """
    if re.search(r'\bi\b', text):
        return False
    sents = [s.strip() for s in re.split(r'[.!?]\s+', text) if s.strip()]
    if not sents:
        return False
    capitalised = sum(1 for s in sents if s[:1].isupper()) / len(sents)
    return capitalised >= 0.95 and text.rstrip().endswith(('.', '!', '?', '"'))


def usable(text):
    n = len(WORD.findall(text))
    return (5 <= n <= 120 and "```" not in text
            and not CJK.search(text) and not CODEY.search(text))


def keep(text, date, rewritten_texts):
    """-> the text if it is the user's own English, else None."""
    t = text.strip()
    if not t or any(b in t for b in NOISE) or not usable(t):
        return None
    if date >= TYPELESS_START:
        norm = re.sub(r'\s+', ' ', t).strip().lower()
        if norm in rewritten_texts or looks_polished(t):
            return None
    return t


# ------------------------------------------------------------ structures ----
# Availability, not correctness. Each is a device a confident speaker reaches
# for without thinking, and a rate near zero means it is simply not in the
# repertoire — a far bigger gap than any agreement error.
STRUCTURES = {
    "modal_perfect": ("情态完成式 would/could have done",
        re.compile(r"\b(would|could|should|might|must)\s+(?:not\s+|n't\s+)?"
                   r"have\s+\w+(ed|en|ne|nt)\b", re.I)),
    "past_perfect": ("过去完成时 had done",
        re.compile(r"\bhad\s+(?:already\s+|just\s+|never\s+)?"
                   r"(been|done|gone|made|seen|taken|given|found|come|written|"
                   r"got|run|set|put|left|kept|failed|changed|worked|started|"
                   r"finished)\b", re.I)),
    "conditional": ("虚拟/条件 if … would",
        re.compile(r"\bif\s+[^.]{3,45}\b(would|could|were|had)\b", re.I)),
    "cleft": ("强调句 it is … that / what … is",
        re.compile(r"\b(it\s+(is|was)\s+[^.]{3,30}\bthat\b|"
                   r"what\s+[^.]{3,30}\s+is\s+that\b)", re.I)),
    "inversion": ("倒装 not only / never / rarely",
        re.compile(r"\b(not only|never before|only then|"
                   r"rarely (do|does|did|have|has)|no sooner)\b", re.I)),
    "participial": ("分词短语开头 Having / Given",
        re.compile(r"(?:^|[.!?]\s+)(Having|Given|Considering|Assuming|"
                   r"Provided|Granted)\b")),
    "concessive": ("让步 although / despite / whereas",
        re.compile(r"\b(although|even though|despite|in spite of|whereas|"
                   r"nonetheless)\b", re.I)),
    "purpose": ("目的 so that / in order to",
        re.compile(r"\b(so that|in order to|so as to)\b", re.I)),
    "contrast": ("取舍 rather than / let alone / as opposed to",
        re.compile(r"\b(rather than|instead of|as opposed to|let alone|"
                   r"if anything)\b", re.I)),
    "hedged_claim": ("有分寸的断言 tend to / arguably / by and large",
        re.compile(r"\b(tend(s|ed)? to|arguably|by and large|for the most part|"
                   r"more often than not)\b", re.I)),
    "relative_which": ("关系从句 which / whose / whom",
        re.compile(r"\b(which|whose|whom)\b", re.I)),
    "nominal_that": ("从句宾语 the fact that / the reason why",
        re.compile(r"\b(the fact that|the reason (why|being)|"
                   r"the point is that)\b", re.I)),
}

# Every one of these is correct English. The problem is that leaning on them
# crowds out the precise word, which is what a narrow range sounds like.
CRUTCHES = ("very", "really", "just", "some", "thing", "things", "good", "bad",
            "get", "make", "do", "use", "maybe", "problem", "nice", "a lot of")

# Correct but stiff. These read as English learned from documents, and they
# mark a non-native speaker harder than a grammar slip does.
STIFF = {
    "wish to": "want to / I'd like to",
    "utilize": "use",
    "commence": "start",
    "assist": "help",
    "regarding": "about",
    "furthermore": "and / on top of that",
    "moreover": "and",
    "hence": "so",
    "thus": "so",
    "kindly": "please / just",
}

# Fluency evidence. Only meaningful on a verbatim transcript: a model trained to
# produce clean readable text deletes almost all of this, and the resulting
# zero says nothing about the speaker.
FILLER = re.compile(r"\b(uh|um|er|ah|mm|hmm|erm)\b", re.I)
REPEAT = re.compile(r"\b(\w+)\s+\1\b", re.I)
REPAIR = re.compile(r"\b(\w{3,})\w*\s+\1\w*\s+\1\w*\b", re.I)


def measure(texts):
    """Range: which devices are in play, how heavily generic words are leaned
    on, how varied the sentence openings are."""
    words = sum(len(WORD.findall(t)) for t in texts) or 1
    joined = " ".join(texts)
    low = joined.lower()

    structures = {}
    for key, (label, rx) in STRUCTURES.items():
        n = len(rx.findall(joined))
        structures[key] = {"label": label, "n": n,
                           "per_1k": round(n / words * 1000, 3)}

    tokens = [w.lower() for w in WORD.findall(joined)]
    counts = collections.Counter(tokens)
    crutch = sum(counts[c] for c in CRUTCHES if " " not in c)
    crutch += sum(low.count(c) for c in CRUTCHES if " " in c)

    starts = collections.Counter()
    for s in re.split(r'(?<=[.!?])\s+', joined):
        w = WORD.findall(s)
        if w:
            starts[w[0].lower()] += 1
    top5 = sum(c for _, c in starts.most_common(5)) / (sum(starts.values()) or 1)

    return {
        "words": words,
        "structures": structures,
        # >= 0.1 per 1000 words, so a single accidental use does not count
        "structures_live": sum(1 for v in structures.values() if v["per_1k"] >= 0.1),
        "structures_total": len(structures),
        "crutch_per_1k": round(crutch / words * 1000, 2),
        "stiff": {k: low.count(k) for k in STIFF if low.count(k)},
        "opening_top5_share": round(top5, 3),
    }


def fluency(texts):
    """Fillers, repetitions and repairs per 1000 words.

    Returns None when the text carries almost no disfluency at all, which means
    it has been cleaned rather than spoken fluently — a polished source must not
    be able to masquerade as a fluent speaker.

    A repair is NOT an error. "so give giving so given this new context" is one
    successful search that landed on the right form; reporting it as three
    mistakes tells someone they got something wrong when they caught it
    themselves.
    """
    words = sum(len(WORD.findall(t)) for t in texts) or 1
    joined = " ".join(texts)
    fillers = len(FILLER.findall(joined))
    if fillers / words * 1000 < 5:
        return None
    return {
        "words": words,
        "filler_per_1k": round(fillers / words * 1000, 1),
        "repeat_per_1k": round(len(REPEAT.findall(joined)) / words * 1000, 1),
        "repair_per_1k": round(len(REPAIR.findall(joined)) / words * 1000, 2),
    }
