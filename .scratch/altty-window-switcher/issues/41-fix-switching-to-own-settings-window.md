# 41 — fix crash when switching to Altty Settings

Status: resolved

## Reproduction and evidence

User: open Settings, activate another application, then Option-Tab back to Altty
Settings. Two Altty crash reports (2026-09-23 22:54:45 and 22:55:00) both show
EXC_BREAKPOINT/SIGTRAP and "Must only be used from the main thread".
The failing background-thread stack is AccessibilityQueryScheduler →
AXWindowReader.raiseWindow → AXUIElementPerformAction → accessibilityPerformRaise
→ NSWindow.makeKeyAndOrderFront → NSWMWindowCoordinator's main-thread assertion.

`scripts/check-self-window-focus.sh` reproduced the failure in a disposable process
with real AppKit windows and the production accessibility adapter (exit 133).
Evidence: `.build/self-window-regression/red.log` and the matching probe crash
report. This does not crash or alter the user's running Altty process.

## Fix

AccessibilityQueryScheduler treats its own PID as local AppKit work and executes
that work synchronously on MainActor. External-process requests retain background
workers, capacity limits, cancellation, and the reserved interactive slot. This
covers raising, deminimizing, semantic enrichment, and focused-window reads through
the scheduler, rather than patching only the one AXRaise call.

## Regression

The real fixture passes 20 self-window focus sequences (mandatory SkyLight plus
AXRaise), 4 minimized-window restorations, enrichment, and exact focused PID/WID
verification. The deterministic scheduler test checks both interactive/background
priorities: own PID executes on main; remote PID executes off main.

Final checks: 140 tests passed; real self-window gate passed; remote focus gate
passed 24 transitions plus 2 minimized restorations (max observed 77 ms). Arm64
build 2026092306 and its ZIP passed release verification and replaced `dist/`.

User acceptance: switching back to Altty Settings no longer crashes. Further
signing/distribution work is waiting for the user's developer certificate.
