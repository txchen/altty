# 24 — Add a mouse wheel reversal toggle

Status: resolved

## Scope

Add one persistent General setting, "Reverse mouse wheel direction", off by
default. Reverse both axes of mouse scrolling relative to the current
macOS direction. Preserve delta magnitude, acceleration and modifiers. Trackpad
scrolling and its momentum pass through unchanged. Do not
change system preferences, add speed/smoothing controls or add per-app rules.

The user explicitly requested Scroll Reverser's proven identification logic
across multiple mice instead of limiting this to discrete wheels. Adapt the
classifier and CGEvent/IOHID compatibility path from
[Scroll Reverser source](https://github.com/pilotmoon/Scroll-Reverser/blob/187bf3945b6107cd8486327c6165f32e523535a4/MouseTap.m).
Use the same recent-multitouch and momentum heuristics for continuous scrolling,
with passive gesture observation and a separate active scroll tap. Keep the UI
to one toggle; omit upstream speed, step size, axis and trackpad controls.
Include Apache-2.0 LICENSE/NOTICE in the source tree and packaged application.
Resolve the private HID compatibility symbols at runtime, isolated in Input;
if unavailable, report failure rather than claiming reversal is active.

## Acceptance

- One accessible checkbox; saved setting migrates from v1–v3 with reversal off.
- Enable only after settings persistence succeeds and Accessibility and Input
  Monitoring are ready. Request permissions only through an explicit user action.
- Reversal works independently of SkyLight readiness and switcher Exceptions.
- Disabled, revoked, failed, or quitting releases the event tap and passes input.
- No network, idle polling, synthetic reposting, key capture or gesture interception.
- Synthetic CGEvent and engine tests cover both directions/axes, fractional
  deltas, trackpad/momentum pass-through, save failure, permission recovery,
  restart migration, and event-tap lifecycle/failure.
- Real mouse/trackpad validation remains for the user's local session; do not
  enable reversal or change their scroll configuration during remote work.

## Resolution

Implemented schema v4 migration, the General checkbox and permission recovery,
engine lifecycle effects, upstream-derived classifier and CGEvent/HID reversal,
and bundled Apache-2.0 attribution. No mouse-model-specific settings were added.

Validation: 112 tests in 16 suites passed with the native Swift build backend;
development app and release dry-run ZIP built successfully; release signature,
contents (including license/NOTICE), checksum and Ruby release contracts passed;
`git diff --check` passed. These are automated/synthetic checks, not hardware
validation. No live scroll taps were enabled and no user scroll preferences were
changed. Manual mouse/trackpad/Safari testing is documented in README.md.
