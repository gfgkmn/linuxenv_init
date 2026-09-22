-- allow-sheet.applescript  [report|raise]
--
-- Chrome 144+ asks permission for EVERY incoming remote-debugging connection
-- with a sheet titled "Allow remote debugging?". The sheet attaches to ONE
-- Chrome window - frequently not the frontmost - so users miss it and every
-- client "times out". Its buttons expose only a description (not a name):
-- "Turn off in settings", "Cancel", "Allow", nested ~7 groups deep.
--
-- The Allow button CANNOT be pressed programmatically: Chrome ignores AX
-- `click`/`AXPress` on this security prompt, and synthesizing a real input
-- event to approve it is a security bypass (and blocked by the harness).
-- So `raise` brings the sheet's window to the front so the human sees it.
--
-- Output: "SHEET on: <window title>" (plus "RAISED" in raise mode),
--         or "none" if no sheet is showing.
-- Requires Automation + Accessibility permission for the calling host app.

on run argv
  set mode to "report"
  if (count of argv) > 0 then set mode to item 1 of argv
  tell application "System Events" to tell process "Google Chrome"
    repeat with w in windows
      try
        repeat with s in sheets of w
          if (name of s) is "Allow remote debugging?" then
            set out to "SHEET on: " & (name of w)
            if mode is "raise" then
              set frontmost to true
              perform action "AXRaise" of w
              set out to out & linefeed & "RAISED"
            end if
            return out
          end if
        end repeat
      end try
    end repeat
  end tell
  return "none"
end run
