# 42 — prevent stalled shortcut transactions after inventory refresh

Status: resolved

## Live evidence

User reports that both Option-Tab and Option-Grave permanently stopped opening
the panel. Build 2026092306, PID 47239, was preserved for inspection. Main thread
was idle; Altty's passive event tap was enabled; secure input was off; readiness
was Ready. A read-only chord-only observer captured both shortcuts while the
user confirmed neither responded. Release hardening denied debugger attachment.
The old logs lack input/transaction state, so the exact live internal state
cannot be proved retrospectively. No permission reset was used as a diagnosis.

## Reproduction

`ALTTY_SWIFT_BUILD_SYSTEM=native scripts/test.sh --filter SwitcherReentrancyTests`
reproduces the failure using the production engine and inventory actor, pausing
one snapshot response while focus verification completes. The inventory refresh
then resurrects the completed session in `verifying`, without a live completion
task. The next invocation produces no panel, and the application's committed
transaction wait has no completion event to resume it.

Old code: two failing expectations in
`.build/input-stall/regression-red.log`. Fixed code:
`.build/input-stall/regression-green.log`.

## Fix and scope

After an inventory actor hop, revalidate the transaction and read the current
session instead of assigning a pre-await copy. Also revalidate after recording
the final focused window, so a stale completion cannot end a replacement session.
Regressions cover completion, confirmation, navigation, session replacement and
late focus completion. Persist bounded-field shortcut metadata in Unified Log
(registered chords and transaction stages only, no ordinary typing or titles)
to distinguish input delivery from a blocked transaction on any recurrence.

This is a confirmed defect matching the symptom, not proof of the inaccessible
state in the user's old process. Physical acceptance of the replacement remains
a separate gate.

## Validation and handoff

144 tests in 21 suites pass. Real focus fixtures: 24 external transitions with
zero failures (max 64 ms), two minimized restorations, 20 own-window raises and
four own-window restorations pass. Build 2026092307 and its ZIP pass release
verification and replace `dist/`. Running PID 55239. The previous live process's
sample, chord trace and Unified Log are saved under `.build/input-stall/`.

The new ad-hoc build reports Accessibility unavailable at 23:15:56, unlike the
old live failure, which was Ready. User was asked to reauthorize the new bundle.

Follow-up: user confirmed reauthorization. Running build 2026092307, PID 56015,
reported Accessibility available at 23:16:53. The subsequent live trace contains
38 physical Option-Tab presses and 38 Carbon callbacks, zero unmatched presses,
13 started and 13 ended transactions, and 12 panel presentations. No unfinished
transaction remains in this captured sequence. Evidence:
`.build/input-stall/reauthorized.log`. This confirms the observed All-Windows
sequence stays responsive; Current-App and longer-term recurrence remain unproven.
