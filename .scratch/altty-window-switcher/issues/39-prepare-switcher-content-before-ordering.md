# 39 — prepare switcher content before ordering the panel

Status: resolved

## Report

One intermittent occurrence of the panel appearing empty, then filling in within
less than one second. User could not reproduce it consistently. Build 2026092302
was otherwise accepted for further use.

## Evidence and correction

A real NSPanel subclass inspects existing table cell views immediately before
`orderFrontRegardless`, without creating them. The old implementation failed:
visible rows (including row 17 after reopening at the end of an overflowing list)
were absent and had no laid-out content. Log: `.build/first-frame-red.log`.

`show` now sizes/positions the hidden panel, lays out its content, scrolls to the
selected row, settles layout again, and renders its backing buffer before ordering
it on screen. This fixes an observed first-frame readiness defect. It is consistent
with the reported symptom, but does not establish that the user's intermittent
compositor-visible blank was reproduced or that no other cause remains.

Performance logs now include `panel_preparation` duration. The existing
`shortcut_to_panel_presentation` timestamp is recorded after presentation work,
not before layout/rendering begins. Logs contain no window titles or content.

## Regression and acceptance

The first-frame regression runs 100 open/close cycles, alternating 1/3/7/24 rows,
first/last selection, compact/comfortable density, and both switcher modes. It
checks existing visible cells and their positive content geometry before ordering,
and full selected-row visibility afterwards. It yields between cycles so the
stress fixture does not starve unrelated concurrent timeout tests.

Actual macOS compositor behavior under the user's workload remains an observation
gate. No stable reproduction of the original intermittent visible blank exists.

Validation completed: 139 tests in 20 suites passed; 24 visual comparisons passed
without baseline changes; arm64 build 2026092303 passed release verification.
Candidate: `.build/first-frame-release/Altty.app`. The accepted running build and
`dist/` were not replaced during this investigation.
