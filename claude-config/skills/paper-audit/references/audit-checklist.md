# Audit checklist

Run against the user's draft. Every item produces either "covered" or a finding.
**Findings are reported as a list, never applied to the draft.** State where in
the draft the problem is, what is wrong, and what would fix it — then stop.

Order the report by cost of being wrong: factual errors first, then gaps, then
imprecision.

## A. Factual

1. **Numbers against the paper.** Every figure quoted in the draft, checked
   against the source. Report mismatches with both values.
2. **Claims against the paper.** Anything stated as the paper's finding that the
   paper does not state, or states with a hedge the draft dropped.
3. **Right conclusion, wrong reason.** The draft reaches a correct result by an
   argument that does not hold. This is the most valuable class of finding and
   the easiest to read past, because the conclusion looks fine.
4. **Attribution.** Claims the user reasoned out themselves, presented as the
   paper's. Both belong in the note; conflating them does not.

## B. Mathematical

5. **Symbols.** Every symbol used before it is explained. The draft is
   colloquial, so a symbol may be described in words rather than defined —
   that counts as explained.
6. **Skipped steps.** A derivation that jumps. Report which step is missing;
   the augment pass supplies it.
7. **The obstacle.** For each method: does the draft say what goes wrong if you
   do the obvious thing? A method described only as a procedure has lost the
   reason for its shape.
8. **Unavailable quantities.** Which quantities are measured, which are known
   constants, which are genuinely unobtainable. Confusing "cannot be computed"
   with "need not be computed" produces class-3 findings.
9. **Demonstration numbers.** If the draft invents example numbers, does their
   dispersion match the theoretical distribution? Tidy numbers teach a wrong
   variance intuition and lead to wrong implementation criteria.

## C. Coverage

The draft is written from understanding, which means it covers what the user
found interesting and silently skips the rest. That is the one systematic
weakness of this workflow, and this section is its counterweight. Report what is
absent; do not fill it in.

10. **Paper type.** Method / analysis / theory / benchmark. Type determines
    which of the following actually apply.
11. **Datasets and splits.** Sizes, provenance, preprocessing, what was held out.
12. **Every figure in the body.** Was each one read and explained? Figures are
    the most commonly skipped part of a paper.
13. **Appendix.** Ablations, results on other models or datasets, second
    metrics, the authors' own caveats. The body shows the best setting; the
    appendix says how extreme that setting was.
14. **Baseline fairness (method papers only).** Missing strong baselines,
    unequal hyperparameter budgets, gains inside the error bars, unequal compute,
    contamination, ablations that do not isolate the claimed component.
15. **Limitations, in three kinds, kept apart.** What the authors concede; what
    their data supports but they did not say; what the reader objects to. The
    third kind must be checked against the source before it is reported.
16. **Position in the literature.** Where the tools came from; which
    same-lineage papers agree and which contradict. Contradictions within one
    lineage are the highest-value content in a note and never appear in the
    paper itself.
17. **Reproduction.** Code, data URLs, key hyperparameters, compute scale, the
    step most likely to go wrong. Plus: if only one experiment could be run to
    test this paper's robustness, which one?

## D. Delivery

18. **Links.** Bare mentions of other notes that should be wiki links;
    section-level references that should target headings rather than files;
    reciprocal links added to the notes being linked.
19. **Rendering.** Formulas, embeds and collapsible blocks verified in Obsidian
    itself, not merely parsed. See `paper-recipe/references/delivery.md`.

## What not to report

- Register, phrasing, sentence length, colloquialism. Not defects here.
- Organisation, unless a claim depends on something introduced after it.
- Anything you would fix by rewriting rather than by adding.
