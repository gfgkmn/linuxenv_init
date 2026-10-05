---
description: Rewrite text as ~80% ASD-STE100 — short sentences, plain words, one idea each
allowedArgs: (none → my previous reply), <file path>, or pasted text
---

Rewrite the target into Simplified Technical English, at about 80% of ASD-STE100.
The target is `$ARGUMENTS`. With no arguments, rewrite your own previous reply.

## Rules

- An instruction takes 20 words or fewer. A description takes 25 words or fewer.
- Write one instruction per sentence, and one topic per paragraph.
- Use the active voice. Name who does what.
- Use simple tenses only: imperative, infinitive, simple present, simple past, simple future.
- Give each thing one name, and keep that name everywhere. Never vary a term for style.
- Prefer the common word. Drop metaphor, idiom and irony.
- Keep numbers, identifiers, paths, commands, code and quoted output exactly as they are.

## The 80%: where accuracy beats the rules

The standard was built for maintenance procedures, not for findings. Keep these,
even when a rule says otherwise:

- Words that separate certainty from doubt: proved, measured, did not verify, assumption.
- A conditional sentence when the fact itself is conditional.
- Terms of art — inode, event tap, container, runtime — renaming them loses meaning.

If a sentence cannot obey a rule without losing accuracy, keep the accurate sentence.

## Scope

- Rewrite prose only: answers, README files, runbooks, error messages, tool and skill
  descriptions, commit messages.
- Never rewrite code, logs, or sample output.
- Add no facts. Remove no facts. Change no conclusion.

## Output

Print the rewritten text. Then add up to three bullets naming what the constraint cost
— the judgement, nuance or comparison that the rules forced out.

For a file target, print the rewrite first. Write the file only if the user asks, or if
they passed `--write`.

(This file summarises the ASD-STE100 rules. ASD holds the copyright to the specification
and its word list; neither is reproduced here.)
