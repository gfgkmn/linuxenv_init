---
name: step-back
description: Leave the current frame on a hard problem and reason from first principles - why does this problem exist at all, is it the right problem, what would a fresh start look like. Use when a second fix for the same symptom fails, when workarounds pile up, when a result contradicts a prediction, when the task is a design, a diagnosis or a trade-off with no clear procedure, or when the user says they are stuck or asks to think from first principles.
---

# Step back

Stop solving. The aim is not a better fix inside the current frame. It is to find out whether the frame is right.

Skip this on a well-structured task with a known procedure. There it costs time and adds nothing.

In co-op mode, put the question of step 2 to gfgkmn before you answer it yourself, in a `>>> THINK FIRST` block. Their answer, right or wrong, is the valuable part.

## 1. Describe the problem before touching a solution

- State the goal one level up: who needs what, and how will they know they have it?
- List what is actually known, and how each item is known: measured, read, or assumed.
- Separate the constraints that are real from the ones inherited from the current approach.
- Say which details decide the outcome and which are noise.

## 2. Ask why the problem exists

- Trace back the choices that led here. Which one created this problem?
- For code, read the history (`git log`, `git blame`, old PRs): which designs were deliberate, which are leftovers, and which solve a problem that no longer exists?
- Can the choice be undone, so the problem disappears instead of being solved? Deleting the need beats meeting it.

## 3. Check the problem statement

- Is this a symptom taken for a cause?
- Is this a means taken for an end? What was the request trying to achieve?
- Is there a more valuable problem next to this one? If so, name it.

## 4. Look from outside

- What would a strong engineer do who arrived today, knowing the goal but none of our path?
- Which other field has a problem of this shape, and what is its standard answer?

## 5. Attack the current best plan

- Assume it is wrong. Take the side of its strongest critic.
- What evidence, counterexample or edge case would defeat it? Go and look for it; do not only imagine it.

## 6. Decide

- Choose one: continue, change the approach, or change the problem.
- For the chosen option only, follow the consequences two steps out: other modules, how people will use it, complexity, cost of upkeep.
- Say the decision and the reason in two or three sentences. Changing the problem needs gfgkmn's agreement.
