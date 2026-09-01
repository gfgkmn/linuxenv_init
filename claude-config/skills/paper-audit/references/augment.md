# Augment

Everything here is an addition placed **beside** the user's prose. Nothing here
licenses editing a sentence. When an addition cannot be made without changing a
sentence, it is not an addition — flag it in the audit instead.

## Formulas

The draft describes quantities in words. Add the formula next to the sentence
that describes it; the sentence stays.

> Draft: "the second shell holds twice the volume of the first"
> After: the sentence, then the formula block, then the symbol gloss.

Every symbol gets its meaning, its range or dimension, and a concrete value
where one exists. State the geometric or physical reading, not just the type.

The constant that looks decorative is usually the one worth explaining: a
normalisation factor is often exactly where the estimated quantity enters.

## Derivations

Where the audit found a skipped step, write the intermediate steps out. Aligned
block, one operation per line, each line annotated with what was done. Keep:

- the substitution of the general form into the special case, including which
  terms become 0 or 1
- the full expansion of any approximation, with the discarded terms shown and
  the reason for discarding them
- how a closed form was obtained
- order-of-magnitude estimates, derived rather than asserted

**Name the textbook tool at the point of use.** Cumulative distribution,
survival function, law of total probability, delta method, Jensen — the reader
can perform the operation; what they lack is knowing which instrument is being
picked up. A step without its name is where a derivation loses people.

## Worked numbers

Add one hand-computable pass per estimation procedure: the raw inputs, each
intermediate as a table, the final value, and the boundary cases. Boundary cases
are what implementation hits first and what papers omit — a value that makes a
logarithm diverge, an index that runs off the end, a sample that must be dropped.

Invented numbers must match the real distribution, variance especially. Tidy
numbers produce a wrong variance intuition and lead to equality tests where a
statistical test is required.

## Figures

Two kinds, and they are not interchangeable.

**Mechanism figures** — drawn, showing how the method works. Placed in the
method section. Test: seen alone, does it recall the algorithm?

**Paper figures** — cropped from the PDF, placed beside the passage that
discusses them, with a caption naming the source figure and page. Every figure
the draft discusses should be embedded.

Procedure for both: `paper-recipe/references/figures.md`.

## Reference infrastructure

Sentence-level deep links back to the PDF, built after the draft exists — the
claims worth anchoring are only knowable once the note is written. Procedure and
delivery checks: `paper-recipe/references/delivery.md`.

## Long derivations

When the mathematical scaffolding a derivation needs grows longer than the point
it supports, split it: one sentence in the main line saying what the result is
and what it is for, the full derivation in a collapsed block (`> [!note]-` in
Obsidian). A reader who skips it loses nothing from the argument; a reader who
opens it gets the version that does not skip steps.

## Order of work

1. Read the draft through once without touching it.
2. Run the audit; deliver the findings list; wait.
3. Augment only after the user has responded to the findings — their answers
   may change what needs adding, and augmenting first wastes the work.
