---
name: ui-craft
description: How gfgkmn wants interface work done - show variants for visual decisions, the standing design stances, the checks for keeping complexity inside the system, and the standard for motion. Use for any work on how an interface looks, feels, is laid out, is navigated or moves, and before reviewing a UI.
---

# UI craft

## Visual decisions: show variants

For a request about how something looks or feels (layout, spacing, density, interaction flow, visual hierarchy), gfgkmn cannot specify the answer in advance but recognizes it on sight. One implementation followed by "is this right?" gives one sample per round trip.

- Build three treatments that differ in their organizing idea, not the same layout in three accent colors.
- Put them side by side on one page that can be reviewed on a phone. Use the Artifact tool's design type where it is available.
- After gfgkmn picks, ask why that one, and record the answer. That sentence is the requirement they could not state up front; it is worth more than the chosen variant.
- Skip variants when the visual direction is already given, or when the change is mechanical: a copy fix, a known-correct alignment.

## Stances

Things to attend to, not conclusions. A verdict about one screen expires when the screen changes and does not belong here.

- **Keyboard first.** Every flow can be completed without the mouse, including state switches that would otherwise need a click. When a modal or popover opens, focus lands where the keyboard can act at once. Check this; do not assume it.
- **Shortcuts scale by mode, not by modifier.** More chords use up the memorable combinations and collide with the OS. A mode plus a plain key multiplies the space. Modes pay off only on surfaces used daily, with a visible mode indicator and real undo. Modal editing is gfgkmn's own preference; on anything shipped to other people, convention wins unless gfgkmn says otherwise.
- **Follow convention unless there is a reason not to.** An experienced user should be able to guess how the app works from comparable apps. A capability they expect to be permanent (revoke, reset, undo) is not a temporary affordance.
- **One visual language.** Roundness, sharpness, palette, button treatment: choose once and hold it across every tab. Two panels doing the same kind of job must not look like they came from different apps.
- **Judge from the user's side.** Ask what a real session looks like, above all the first one, with no data yet. An empty screen with no next step is a defect.

If this list grows past a handful of entries, it has started collecting specifics. Prune it.

## Complexity belongs to the system, not the user

Review a flow against these:

- What the system can decide, it does not ask the user.
- What is not useful right now is not on screen.
- What can be done for the person is done.
- The same thing works the same way everywhere.
- Every press gets a response, and a second press can take it back.
- Nothing interrupts what the person is doing.
- Frequent actions are easy; actions that lose data are hard to hit by accident.
- The interface explains itself.

After fixing, use the flow yourself once to confirm.

## Motion

Find motion work by state change, not by component. Whenever anything changes state (appears, disappears, moves, resizes, changes content or icon, a number ticks, pressed, hovered, loading, done, failed), ask: can the user follow this change, or did it jump?

A good transition:

- Explains what happened: where the thing came from, where it went, what it relates to. It is not decoration.
- Uses the project's one language: the same kind of change gets the same curve and timing. Unify what exists before inventing.
- Is restrained: fast and light. Actions the user repeats are faster still. Less motion beats wrong motion.
- Follows the hand and can be interrupted: dragging and resizing track directly, and a new action during an animation picks up naturally.
- Costs no performance: only what must move moves, and long content stays at full frame rate. Measure before delivering.
- Adds no new problem: no jitter, flash, reflow or overflow, and it respects the system's reduce-motion setting.
- Holds on phone, narrow window, wide screen, light and dark.
