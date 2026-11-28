---
name: ui-craft
description: How gfgkmn wants interface work done - settle the application's purpose, style and palette first, design each device for what it is, cover every screen and state before building, show variants for open visual questions, keep complexity inside the system, and the standard for motion. Use for any work on how an interface looks, feels, is laid out, is navigated or moves, and before reviewing a UI.
---

# UI craft

The sections follow the order of the work: what the application is, what each device is for, what the whole design covers, and only then the single screen. Each one says what to settle, not what the answer is. The answers are yours to find.

A mechanical change (a copy fix, a known-correct alignment) needs none of this.

## 1. The application first

Before any screen, settle these three and write them where the project keeps its design decisions. If the project already has them, read them and stay inside them.

- **Purpose.** What the application is for, who uses it, and in what moment: a glance while doing something else, or a long sitting. Every later choice is judged against this.
- **Style.** One family for the whole product: glass, flat, realistic, cartoon or another. It sets roundness, depth, texture, icon treatment and type.
- **Palette.** The few colours and what each one means. A colour that carries a meaning in one place carries the same meaning everywhere.

These hold across every screen and every device. Two panels doing the same kind of job must not look as if they came from different applications. If any of the three is undecided, that is the first question for gfgkmn, before any layout.

## 2. Each device for what it is

A device is not a larger or smaller copy of another one. For each device the product runs on, start from its traits:

- screen size and viewing distance;
- input: touch, pointer, keyboard, crown, voice;
- how long a typical use lasts: seconds on a watch, minutes on a phone, hours at a desk;
- how fast it responds, and where and in what posture it is used.

Then decide what this device is for in this product, and give it that. Not every feature belongs on every device. A difference between two devices' designs must come from a difference between the devices, not from a wish for variety.

Follow each platform's conventions unless there is a reason not to. An experienced user should be able to guess how the app works from comparable apps, and a capability they expect to be permanent (revoke, reset, undo) is not a temporary affordance.

## 3. The whole design before the build

For a new surface or a redesign:

- List every screen the work touches and every state of each: first run with no data, loading, empty, full, very long content, error, offline.
- A screen or state that was never designed gets filled in by improvisation during the build. Design it, or say plainly that it is still open.
- Use real content at real volume. A layout that works with three short rows can fail with three hundred long ones.
- Each screen has one thing it is for. Decide what that is and let the hierarchy show it.
- A pick among variants closes that one question, not the design. Judge for yourself when the design covers enough to build, and tell gfgkmn what you left open.

## 4. Open visual questions: show variants

For a question about how something looks or feels (layout, spacing, density, interaction flow, visual hierarchy), gfgkmn cannot specify the answer in advance but recognizes it on sight. One implementation followed by "is this right?" gives one sample per round trip.

- Build three treatments that differ in their organizing idea, not the same layout in three accent colors. Each must be a serious answer for this application and this device; a variant that exists only to be different wastes the round.
- Put them side by side on one page that can be reviewed on a phone. Use the Artifact tool's design type where it is available.
- After gfgkmn picks, ask why that one, and record the answer. That sentence is the requirement they could not state up front; it is worth more than the chosen variant.
- Skip variants when the direction is already given.

## 5. Complexity belongs to the system, not the user

Review a flow against these:

- What the system can decide, it does not ask the user.
- What is not useful right now is not on screen.
- What can be done for the person is done.
- The same thing works the same way everywhere.
- Every press gets a response, and a second press can take it back.
- Nothing interrupts what the person is doing.
- Frequent actions are easy; actions that lose data are hard to hit by accident.
- The interface explains itself.

## 6. Motion

Find motion work by state change, not by component. Whenever anything changes state (appears, disappears, moves, resizes, changes content or icon, a number ticks, pressed, hovered, loading, done, failed), ask: can the user follow this change, or did it jump?

A good transition:

- Explains what happened: where the thing came from, where it went, what it relates to. It is not decoration.
- Uses the project's one language: the same kind of change gets the same curve and timing. Unify what exists before inventing.
- Is restrained: fast and light. Actions the user repeats are faster still. Less motion beats wrong motion.
- Follows the hand and can be interrupted: dragging and resizing track directly, and a new action during an animation picks up naturally.
- Costs no performance: only what must move moves, and long content stays at full frame rate. Measure before delivering.
- Adds no new problem: no jitter, flash, reflow or overflow, and it respects the system's reduce-motion setting.

## 7. Look at the real thing

Judge the rendered result, not the code. Run it on the device or simulator at its real size, in light and dark, at the narrowest and widest window it supports, and compare it with the agreed design. The `screenshot-review` skill captures the screens. Then go through one real session from the user's side, starting with the first one.

## gfgkmn's own preferences

These are personal tastes, not principles. They apply to tools gfgkmn uses every day. On anything shipped to other people, platform convention wins unless gfgkmn says otherwise.

- Every flow can be completed from the keyboard, and focus lands somewhere useful when a panel opens.
- When more shortcuts are needed, prefer a mode plus a plain key over more modifier chords, with a visible mode indicator and real undo.
