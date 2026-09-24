# 37 — repair real window focus and switching presentation

Status: resolved

## Report

User saw frequent "Unable to switch to that window" without reaching the selected
window, slow panel appearance, and an unwanted right-side scrollbar.

## Cause and correction

A two-window real AppKit fixture reproduced SkyLight returning success while AX
focus remained on the first window for 500 ms. Four alternating requests failed
2/4 times. Moving the event outside resize handles and omitting mouse-up did not
alone fix this. Adding AXRaise for the exact target after the mandatory SkyLight
request produced 4/4 correct focus observations. Integrated that sequence into
WindowFocusExecutor, used by normal focus and failure recovery, with transaction
checks between asynchronous stages. AXRaise is best effort; the exact PID/WID
postcondition remains the success criterion. Updated ADR-0001 to describe the
required ordering step rather than claiming SkyLight alone suffices.

Focus mouse events now target far beyond the bottom-right instead of -1/-1 and do
not complete a click. Panel debounce is 40 ms rather than 125 ms. The list retains
keyboard/mouse-wheel navigation and selection scrolling without a visible scroller.

## Validation

`scripts/check-window-focus.sh` runs the production executor against two disposable
AppKit processes with three windows each. 24 forward/reverse same-app and cross-app
requests plus two minimized-window restorations verified successfully (max observed
focus time 78 ms in this run). 134 automated tests passed. This real regression is
a required switching gate; mocks and screenshots alone are not sufficient.

The previous ad-hoc signing permission issue is independent: replacement binaries
may require the user to replace the existing macOS privacy permission entry.
