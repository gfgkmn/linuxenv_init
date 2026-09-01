---
name: screenshot-review
description: Capture app screenshots yourself — a whitelisted macOS window, a booted iOS simulator, or a batch — and lay them out as a phone-readable review gallery. Use when the user needs to SEE a UI to judge it (layout, spacing, "does this look right"), when they would otherwise screenshot manually and paste, when preparing screens to review away from the desk, or when they ask for a screenshot / gallery / visual diff of an app.
allowed-tools: Bash, Read
---

# Screenshot review

The user is the only component that can judge whether a UI looks and feels
right. They are *not* needed to build, launch, navigate to, and capture the
thing being judged. This skill removes that mechanical half so a judgment costs
one look instead of a five-minute setup.

Two rules govern everything below:

- **Capture is gated by an allowlist you cannot widen.** `enforce-shot.sh`
  denies bare `screencapture`; `cc-shot.sh` is the only sanctioned path and it
  refuses any target absent from `~/.claude/shot-allowlist`.
- **Unattended galleries are off unless the user armed them.** Ask before
  capturing a batch and before publishing, unless the flag file says otherwise.

## Capture

    ~/.claude/scripts/cc-shot.sh list                 # what may be captured
    ~/.claude/scripts/cc-shot.sh window <ProcessName> # one app window
    ~/.claude/scripts/cc-shot.sh sim                  # booted simulator
    ~/.claude/scripts/cc-shot.sh displays             # real vs virtual monitors

Each prints the written path on stdout. Read that file to actually see it.

**Window mode** captures the window's own content by CGWindowID, so an
overlapping window or a notification banner is never included. It finds
minimised windows and windows on other Spaces too; those may return a cached
frame, so the filename gets an `-offscreen` suffix and a warning goes to
stderr. Treat such a shot as possibly stale — say so rather than presenting it
as current.

To add a target, the **user** edits `~/.claude/shot-allowlist` (one process
name per line). Never suggest working around the allowlist; propose adding to
it instead.

**Simulator mode** reads the simulator's framebuffer, so it cannot pick up
anything else on screen and works with no Simulator UI window open. It is the
safe path — prefer it whenever the platform allows.

**displays mode** cross-checks Quartz against `system_profiler`. Universal
Control presents another Mac's screen as an extra online display; only displays
that `system_profiler` also lists are physically attached. Use this before
reasoning about monitor geometry.

## Driving the app to a screen

`xcrun simctl io <UDID> tap` does **not** work on current iOS runtimes — taps
are silently ignored and every screenshot comes back byte-identical. Verify by
comparing file sizes before believing a navigation step worked.

Capturing more than the first screen therefore needs **XCUITest**, which is a
property of the project under test, not of this skill. The project must supply
a `bundle.ui-testing` target whose test walks the flow by accessibility
identifier and calls `XCUIScreen.main.screenshot()` at each stop; screenshots
come out of the `.xcresult` via `xcrun xcresulttool`. Without such a target,
say plainly that only the launch screen is reachable — do not fake a tour.

## iOS capture loop

    xcrun simctl boot <UDID>; xcrun simctl bootstatus <UDID> -b
    xcodebuild -project X.xcodeproj -scheme S \
      -destination 'platform=iOS Simulator,name=<device>' \
      -derivedDataPath /tmp/ccdd build
    xcrun simctl install <UDID> /tmp/ccdd/Build/Products/Debug-iphonesimulator/X.app
    xcrun simctl launch <UDID> <bundle-id>
    ~/.claude/scripts/cc-shot.sh sim

Take the `.app` from `Debug-iphonesimulator` explicitly. A bare
`find -name "*.app"` may hand back the watchOS build, which installs with a
misleading "Unable to Install" error.

Builds are long-running: run them in tmux per the cooperation protocol so the
user can watch, and wait with `~/.claude/scripts/tmux-exec.sh`.

## Gallery

    /opt/homebrew/bin/python3.10 ~/.claude/scripts/cc-gallery.py \
        MANIFEST.json OUT.html --title "..." --build "..."

Manifest entries: `path` (required), `name`, `group`, `meta`, `note`. `group`
becomes a section; `note` is the one line saying what changed — that line is
what makes a gallery reviewable rather than just a pile of images.

Publish `OUT.html` with the Artifact tool. Republishing the same file path
keeps the same URL, so a gallery can be refreshed in place across a session.

The generator sizes portrait and landscape captures separately (a Mac window
downscaled to phone width turns its text to mush) and puts every thumbnail in
one fixed box, so a tall phone screen and a wide desktop window occupy equal
card area. It reports the page size against the 16 MB Artifact cap and stops
before exceeding it; typical shots cost ~85 KB each, so roughly 150 fit.

`--from-dir DIR` builds a manifest from every image in a directory when there
is nothing meaningful to say per screen.

## Attended vs unattended

    ~/.claude/scripts/cc-gallery-toggle.sh status | on | off

Default is **semi-auto**: ask before capturing a batch and before publishing.
When the user has run `on`, capture and publish without interrupting — that
mode exists for the hours they are asleep or away.

`cc-gallery.py --auto` exits non-zero while the flag is absent, so the mode is
enforced by the tool rather than by intention.

## Failure modes worth naming

- **Screen Recording permission.** `could not create image from display` means
  the responsible process lacks it. macOS attributes the request to the app
  that started the process chain — for a tmux pane launched from Emacs that is
  Emacs, not tmux and not the terminal. The user grants it in System Settings;
  it cannot be granted programmatically, and macOS re-confirms periodically.
- **No window found.** The process is running but has no capturable window.
  Report that; do not fall back to a screen-region capture.
- **Identical file sizes across a "tour"** mean navigation never happened.
