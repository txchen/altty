# 23 — Fix implementation review findings

Status: resolved

## Scope

The full implementation review at base `47d2f61` identified seven defects:
malformed Cask URLs, Cask filename/token mismatches, first-tap-publication failure,
live session candidates dropped during semantic invalidation, focus notifications
lost before discovery, terminated-process AX observers retained, and synchronous
AX registration/callback work on the main thread.

## Resolution

- Use a concrete validated version in Cask URLs and separate directories with the
  same `altty.rb` filename for current, previous and local artifacts.
- Share tap preflight between CI and isolated regression fixtures. Include new
  files in diff checks, create the Casks directory, reject unrelated changes,
  and explicitly reject non-metadata edits (negated pipelines do not trigger
  Bash's `errexit`).
- Keep authoritative live identities separate from qualified windows so an AX
  read in progress cannot remove or retarget a captured session candidate.
- Replay the latest undiscovered SkyLight focus notification only after snapshot
  validation; discard superseded, destroyed, stopped and cross-Space hints.
- Run AX observer registration, callbacks and removal on a dedicated run loop.
  Remove registrations on application termination and reject obsolete callbacks
  with per-registration tokens, including during PID reuse.

## Validation

The session regression was run before the fix and selected WID 30 instead of 20
after an unchanged live-window reconciliation. The Cask regression also failed
on the original generated Ruby. Both pass after the fixes.

- `ALTTY_SWIFT_BUILD_SYSTEM=native scripts/test.sh`: 101 tests reported passing;
  opt-in live-system smoke bodies are not enabled.
- `swift build --build-system native -c release --arch arm64`: production build
  passed; this is compilation evidence, not signed distribution validation.
- `ruby scripts/test-release-contract.rb`: validates generated Ruby URLs, actual
  workflow Cask filenames, initial publication, upgrades and rejection of changes
  outside release metadata, without Homebrew installation or publication.
- System-adapter tests use a real background run loop with synthetic IPC and
  verify main-thread responsiveness, removal during blocked registration, PID
  reuse and 1,000 observation/removal cycles returning to baseline.

Real keyboard/focus interaction, signed/notarized Homebrew lifecycle and
supported-OS/hardware validation remain the release gates tracked by ticket 22.
