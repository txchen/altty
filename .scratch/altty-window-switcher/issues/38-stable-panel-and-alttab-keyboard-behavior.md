# 38 — stable panel geometry and AltTab-style keyboard behavior

Status: resolved

## Report

Selecting the last visible item moves the list, quick Option-Tab flashes the panel,
and pressing Shift alone during a held session does not select the previous item.

## Upstream behavior

Reviewed AltTab's `Preferences.swift` (default display delay 100 ms and previous
window shortcut Shift) and `TilesView.highlight` (highlight drawing is separate
from item layout). Reference: https://github.com/lwouis/alt-tab-macos . Behavior was
independently implemented; no upstream source or assets copied.

## Reproduction and correction

- Real AppKit regression observed the visible rect change from y=0 to y=10 and
  every row move 10 points when selecting the last of seven rows. Explicit plain
  table style and fixed row heights eliminate the implicit inset. The selection
  remains drawing-only; selection visibility now requires the whole row to fit.
- Restore the quick-tap grace period to 100 ms, matching the upstream default.
  Confirmation still starts immediately on modifier release; the delay only gates
  showing the panel. At 80/99 ms no panel is shown, and a cancelled presentation
  deadline cannot show the panel after confirmation.
- Record Shift rising edges in the existing bounded physical gesture history.
  Consume each edge once as session-only backward navigation, before release.
  Drain the preceding physical press before a newer Carbon callback replaces it.
  A regression reproduced losing a Shift step when callback delivery was delayed.
  Shift outside a held gesture does not open a session. Shift-Tab remains usable.

## Validation

138 tests in 20 suites pass, including real AppKit first-to-last and back geometry,
quick-tap boundaries, repeated Shift, delayed delivery, and out-of-session Shift.
Dark/light, 1x/2x synthetic visual fixtures regenerated for the plain table geometry.
Physical keyboard acceptance remains separate from deterministic callback tests.

The exploratory system-input probe is retained under `.build/input-regression/`.
The physical tap observed the synthesized test chord, but no Carbon callback
arrived even after allowing application startup to finish. This host result is
not a passed native keyboard gate; no claim that synthesis substitutes for the
user trying the replacement build. Logs: `.build/interaction-real-input.log`.
