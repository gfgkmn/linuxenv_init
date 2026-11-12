# Reading through the console

Operating procedure for the agent (a Claude Code session, or any interactive
agent in a tmux pane) for the whole paper session, not only stage 1. The
terminal is the control channel; the console window renders everything worth
reading. The reason is blunt: the terminal cannot render mathematics, and a
reading session is mostly mathematics.

## Setup, on `/paper-audit <pdf-or-dir>`

1. **Confirm tmux.** `$TMUX` must be set; get the session name with
   `tmux display-message -p '#S'`. Without tmux the console has no way to send
   questions back — say so and fall back to terminal-only dialogue.
2. **Extract text** if `paper.txt` does not sit beside the PDF:
   `pdftotext -layout <pdf> paper.txt`. Read it; build the page map.
3. **Start the console and set the route** (one call; it also opens the window):

   ```
   emacsclient -e '(progn
     (load "~/.config/doom/site-lisp/chat-console/chat-console.el" nil t)
     (load "~/.config/doom/site-lisp/chat-console/chat-console-note.el" nil t)
     (chat-console-transcript-clear)
     (chat-console-reading-begin "<tmux-session>" "<paper-dir>"))'
   ```

   If emacsclient fails, Emacs is not running — say so and fall back to
   terminal-only dialogue rather than dying.
4. Push the opening survey (see below), then begin the stage-1 dialogue from
   `SKILL.md`: background before prediction, ask at "setup known, result
   unknown", align the frame before elaborating.

## Channel discipline

The channel is decided by **what the content is about**, never by where the
question came from or how long the answer is. A question typed in the terminal
about the paper's subject is still console material.

| Content | Channel |
|---|---|
| The paper or its subject: explanations, derivations, research and literature summaries, comparison tables, figures, formulas, PREDICT questions, candidate changes to the note | **Console** |
| Tooling and the session itself: config, git, scripts, setup, "is it done", how the workflow works | **Terminal** |

When content goes to the console, the terminal gets one status line naming the
block ("pushed r-4"). Never paste walls of paper text into either channel —
quote the minimum and cite the page.

## Routing, and when the agent is absent

While this session runs, every question from the console page, from `SPC r i`
in a note, and from the Obsidian ask hotkey reaches this agent. Emacs checks
before each question that the routed tmux pane still runs the agent; if not,
it falls back to the note backend (agy), which needs no agent session. The
page's header names the current answerer.

## Pushing content

Write the markdown to a file, then push — never inline through shell quoting:

```
emacsclient -e '(chat-console-render-file "r-12" "assistant" "/path/to/block.md")'
```

- **Ids**: `r-1`, `r-2`, … in order. Reusing an id replaces that block —
  useful for correcting a block, wrong for appending.
- **Echo the user's question first** as a `"user"` block when it arrived
  through the terminal, so the transcript is complete without the page having
  seen it. Questions from the console arrive prefixed `[Console]` (or
  `[Note]`, from a note) and are already echoed by Emacs the moment they are
  sent — do not push a second copy. No prefix means the terminal.
- **PREDICT questions are blocks too**: push the setup and the question,
  render `**PREDICT**` at the top, then wait. Do not reveal the result in the
  same block.
- Check `chat-console-last-render-report` after pushing formula-heavy blocks;
  a KaTeX failure there is invisible unless you look.

## Figures

Generate with wolfram-lazy (build sources with `wlsbuild.py`, rules in
`paper-recipe/references/figures.md`), or crop from the PDF with `pdftoppm`.
Then:

```
cp fig.png ~/.config/doom/site-lisp/chat-console/www/assets/<paper>-<name>.png
```

and reference it as `![caption](assets/<paper>-<name>.png)`. Prefix filenames
with the paper slug — the assets directory is shared across sessions.

## Answering figure questions

`paper.txt` has no figures, and captions are not evidence. When a question
touches a figure — "what does Figure 3 show" — **look at the actual figure**:

1. Render the page: `pdftoppm -png -r 150 -f <page> -l <page> <pdf> pg`.
2. Read the image with your own vision (the Read tool displays it). Axes,
   legends, line shapes, where curves cross — all read from pixels, never
   inferred from the caption.
3. Crop the figure, copy it into `www/assets/`, and push it beside the
   explanation so the user sees what you are describing.

Answering a figure question from the caption alone is guessing and is not
acceptable. The Read tool also renders PDF pages directly (`pages` parameter)
when a quick look is enough and nothing needs pushing.

## Questions coming back

Questions the user asks in the console arrive in your prompt prefixed
`[Console]`, with the selected excerpt quoted when there is one. Treat the
excerpt as the referent of "this"; push only the answer block, since Emacs has
already echoed the question.

## Ending a session

When the user says the paper is done (or asks to export):

```
emacsclient -e '(chat-console-export "<paper-dir>")'
emacsclient -e '(chat-console-reading-end)'
```

The export is a single markdown file plus an `assets/` copy of every
referenced figure — self-contained, safe to move. Tell the user the path.
The conversation itself stays resumable across days via `claude --resume`;
mention that when a session ends mid-paper.

## What the console is not

The console never writes the note. Changes reach the note only as candidate
fences the user takes through the diff. The output of reading is the user's
understanding; the export is reference material, not a draft. Do not offer to turn the
transcript into a note — that is exactly the failure the prose contract in
`SKILL.md` exists to prevent.
