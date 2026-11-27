---
name: retro
description: Review a recent period of work for repeated corrections, bugs, rework and reverts, find their shared causes, and turn each into a check, a structure or a rule. Also runs three audits - historical baggage, cognitive cost, slow spots.
argument-hint: "[corrections|baggage|cost|slow] [period, e.g. 14d]"
disable-model-invocation: true
---

# Retro

Default mode is `corrections`; default period is the last 14 days.

Changing rule files, hooks or skills is on the ask-first list. This skill ends with a proposal; it changes nothing until gfgkmn agrees.

## corrections

1. Collect the evidence for the period: git history (fixes, reverts, a file edited again soon after a change) and, where available, session transcripts in which gfgkmn corrected the agent.
2. Group the items by shared cause. Do not only count what happened; ask what the items have in common.
3. For each cause that could have been prevented, propose the cheapest guard that works, in this order:
   - a mechanical check: hook, test, lint or deny rule, with an error message that says how to fix it;
   - a structure that makes the mistake impossible: a changed interface or layout;
   - a line of prose in the rule files, with a note on why no check was possible.
4. For each existing prose rule that a check now guards, propose cutting it to one line that names the check.
5. Show the list: cause, evidence, proposed guard, cost. Wait for the decision.

## baggage

Read the git history, the key changes and how the architecture evolved. Sort the designs into deliberate, leftover, and "solves a problem that no longer exists". List what can be removed safely, with the evidence for each item.

## cost

Suppose a strong engineer who knows nothing about the project takes over tomorrow. Estimate what it costs them to understand it. Find the confusing names, the over-abstraction, the unclear responsibilities and the code that needs a lot of context. Propose simplifications.

## slow

Find the slowest spots in the period (changes that took longest, steps that stall) and say what could be made faster.
