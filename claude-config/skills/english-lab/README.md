# English Lab

Turns years of your own writing and speech into a daily English drill, and
measures whether the drill lands — without you logging anything.

This file is for the human. `SKILL.md` next to it is the instruction file the
model reads when the skill loads; the two are deliberately different documents.

---

## What it is for

Most language practice fails in the same two places. It teaches material you did
not ask for and will not use, and it has no way of telling whether anything
stuck — so "progress" stays a feeling.

This fixes both by using something you already generate: every message you type
and every sentence you dictate is evidence of what your English can and cannot
do today. From that the system draws practice material, and against that it
checks, later and unprompted, whether what was taught has entered your own
speech.

### The one idea it rests on

**The corpus is the log.** If `weakest link` was taught last week, nothing
records that fact for retrieval — the system searches this week's messages for
it. Answers to the drill arrive by themselves too, because you say them through
your dictation tool, which puts them straight back into the corpus. Nothing is
self-reported, nothing has to be remembered by hand, and the measurement cannot
be gamed by feeling diligent.

### What it measures, and what it refuses to

It measures **range** — which constructions you can actually reach for, how
often you fall back on generic words, how varied your sentence openings are, and
how much hesitation sits in your speech.

It does not count plural `-s`, articles, or third-person agreement. Those are
easy to detect and nearly irrelevant: a listener does not downgrade you for
*"this setting exist"*, they downgrade you for *"very good, very important, very
strange"*. An early version of this tool made exactly that mistake — it measured
what a regular expression could see and let frequency stand in for importance.
`rules.py` opens with the correction, because it is the kind of error that looks
like rigour.

The consequence is that the failure mode this system hunts for is **silence**: a
construction that never appears at all. No error detector can see that.

---

## Files

### In this repository — generic, no personal data

| File | What it is |
|---|---|
| `README.md` | this |
| `SKILL.md` | how the model should teach: priorities, what to look for, how to handle each review state, what never to do |
| `rules.py` | **what gets measured and why** — corpus trust rules, the 12 structures, crutch words, register markers, fluency signals. The part worth reading on its own |
| `english.py` | the whole CLI: pull material, transcribe, measure, age the queue, report |
| `TODO.md` | deferred work, each with its reason |

Two supporting files live elsewhere in the same repository:

| File | What it is |
|---|---|
| `commands/english.md` | the `/english` slash command |
| `hooks/english-daily.sh` | a SessionStart hook, day-locked so it fires once a day across all concurrent sessions rather than every time one opens |

### On your machine — `~/.claude/english/`

Never committed. This is where everything personal stays.

| File | What it is |
|---|---|
| `BASELINE.md` | your findings: the four-year picture, where the gaps are, the model comparison |
| `corpus.jsonl` | your trustworthy own writing, one message per line |
| `speech.jsonl` | verbatim transcripts of your English recordings |
| `queue.jsonl` | what is currently being practised, with its review schedule |
| `graduated.jsonl` | what has proven to have entered your production, with the evidence |
| `metrics.jsonl` | one row per week: range and fluency |
| `cursor.json` | how far each source has been read, so updates stay incremental |
| `reading.json` | word frequencies from material you have read; a cache |
| `eudic_words.json` | your dictionary wordbook, pulled |
| `config.json` | `{"TOKEN": "NIS …"}` — the only credential, and it never leaves this directory |

---

## Using it

```
/english                       the daily drill, inside a session
```

That runs an update and hands the model six real utterances of yours. It then
teaches two or three of them, records what it taught, and checks anything due.

Directly:

```
english.py update              pull new material, transcribe, measure, age the queue
english.py update --rebuild    start over (re-transcribes everything; slow)
english.py drill               today's material
english.py drill --brief       two utterances, what the hook shows
english.py drill --json        the same, machine-readable

english.py add "<item>" --kind structure --note "<一行中文>" --source "<原句>"
english.py drop "<item>"       remove a bad pick
english.py list                the queue, with hit counts

english.py report              weekly markdown into the notes vault
english.py range               the year-by-year range table
english.py eudic pull|cross|push
```

### A normal day

1. A session opens; the hook shows two of your own sentences. Say better
   versions out loud. Nothing is graded.
2. At some point you run `/english`. Six sentences, two or three get taught, the
   rest are left alone. You say the rewrites aloud — through dictation, so they
   re-enter the corpus.
3. Items taught earlier come back when due, in one of three states:
   **已经用上了** (it appeared in real production — nothing to do),
   **复习** (make a sentence with it now),
   **卡住了** (four prompts and nothing; the item was probably a poor choice).
4. On Sunday, `english.py report` writes the week into your notes vault, which
   syncs to phone and e-reader.

### What graduation means

Three or more uses, across two or more distinct weeks, **unprompted**. Three
uses in one day is short-term memory. Uses on the same day as a prompt do not
count. This is the only definition of "learned" the system accepts, and it is
checked against your text rather than your impression.

### Review intervals

They move on evidence, never on the calendar:

- used since the last check → 1, 3, 7, 16, 35, 70 days
- not used → back in two days
- four misses in a row → flagged as a bad item, not a bad memory

Real use beats any drill, so the schedule rewards it by getting out of the way.

---

## Setup

**Requirements:** Python 3.10+, `ffmpeg`, and `parakeet-mlx` (`pip install
parakeet-mlx`) on Apple Silicon. The transcription model downloads on first use,
about 2.4 GB.

**Optional:** a dictionary wordbook token in `config.json`. Without it
everything works except `eudic`.

**Paths.** These are set for one machine and overridable by environment
variable:

| Variable | Default | What |
|---|---|---|
| `ENGLISH_LAB_HOME` | `~/.claude/english` | state directory |
| `ENGLISH_LAB_ARCHIVE` | `~/Documents/ChatgptHistory/Echoes-ALL` | exported chat history |
| `ENGLISH_LAB_VAULT` | an iCloud notes folder | where the weekly report lands |
| `ENGLISH_LAB_ASR` | `mlx-community/parakeet-tdt-0.6b-v3` | transcription model |

Three paths are still hardcoded near the top of `english.py` because they name
specific applications: the CLI session directory, and the dictation tool's
database and recordings. Change them there if your tools differ.

**One constant that matters more than it looks.** `TYPELESS_START` in `rules.py`
is the date a rewriting dictation tool came into use. Before it, everything is
your own; after it, anything that tool touched is excluded, because it changes
word choice as well as grammar and would flatter every measurement. If you use
a different tool, or none, set this accordingly — getting it wrong corrupts the
numbers silently, which is the worst way to be wrong.

---

## Design decisions worth knowing

**There is no word list, and that is deliberate.** An early build chose targets
from a frequency table pairing your generic words with "better" alternatives. It
offered `purely` as a replacement for `just` in a sentence where `just` meant
*merely* — two words a table lists as synonyms and a reader never confuses.
Sense is not countable. The model judges each sentence instead.

**Mining your own corpus for targets is capped by construction.** It can only
give back the range already in it. The most useful finding in the baseline — a
construction absent for four years — came from testing a hypothesis, not from
mining.

**Transcription is verbatim on purpose.** A model trained to produce clean,
readable text deletes fillers, repetitions and self-corrections. Those are not
noise around the measurement, they *are* the fluency measurement; on identical
audio the clean-text model returned about two-thirds the words. Note that this
makes it the wrong tool for ordinary dictation and the right one here — opposite
jobs.

**A repair is not an error.** Searching through word forms and landing on the
right one is a success, not three mistakes. The system reports them separately,
and they call for different responses: an uncorrected error means the rule is
not known, a repair means it is known but not automatic yet.

---

## Limits

A text corpus reaches three of the four things spoken proficiency is usually
judged on: vocabulary range, grammatical range, and fluency. **Pronunciation is
invisible here** and can only be judged live. The system does not estimate it,
and should not be asked to.

The drill is only as good as the material flowing in. If dictation is mostly in
another language, the same few sentences will start repeating within a week.

---

## Privacy

This directory sits in a public repository. Everything personal — your rates,
your sentences, your vocabulary — belongs in `BASELINE.md` in the state
directory. Keep every example in the committed files invented or generic. The
credential lives only in `config.json`, which is outside every repository, and
nothing in the system sends your text anywhere. The one outbound call writes
queue items to your own dictionary account, and only when you ask for it.
