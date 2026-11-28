# Doing

How to carry out a piece of work.

- Decide how you will check a change before you make it: a test, a shape, a loss curve, a grep, a screenshot.
- Before changing a fact, a rule or a name, list every place it lives (code, docs, tests, config, hooks, generated files) and change them together. Then search for the old wording.
- Try the result the way it will be used, from the entry point, before saying it is done.
- For slow or hard-to-reverse work (training, data pipelines, migrations, deployments), run the smallest version first, check it, then scale up.
- When debugging, change the failing script in place with minimal instrumentation instead of writing a new test script. This keeps the investigation on the real code path.
- Make the smallest edit that does the job, and match the style of the surrounding file.
- When something fails, read the error and find the cause before trying again. An ordinary obstacle (a timeout, a missing path, a flaky tool) you work through yourself. Do not rerun the same thing unchanged, and do not guess at variations.
- If the same symptom survives a second fix, or the task itself looks wrong, stop executing and step back.
