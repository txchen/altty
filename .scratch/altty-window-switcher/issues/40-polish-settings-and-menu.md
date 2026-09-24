# 40 — polish settings and simplify the menu

Status: resolved

## Changes

- Menu bar uses an original template window icon with three titlebar dots.
- Normal menu: readiness status, Reverse Mouse Scrolling checkbox, Settings, Quit.
  Accessibility recovery appears only when needed. Technical status rows removed.
- The checkbox uses the same persisted GeneralSettings command as Settings and
  preserves login/list preferences. Tests cover toggling in both directions and
  synchronizing its checked state from the model.
- Removed Check for Updates commands, effects, presentation actions and GitHub
  release action. About documents `brew upgrade --cask altty` for Homebrew installs.
- Settings uses consistent card groups, aligned controls, a native titlebar,
  full-width content, and scrolling in every pane. Exceptions resizes with content.
- About says "for Mac" and displays the actual running OS version instead of
  presenting the minimum deployment target (macOS 15) as the current platform.
- Saving an explicitly enabled mouse reversal preference now requests Input
  Monitoring immediately. Already-authorized requests do nothing. Returning to
  Altty checks readiness again. Recovery offers Show Altty in Finder, selecting the
  exact running app bundle instead of asking the user to locate it manually.

## Permissions boundary

The code still uses Apple's CGRequestListenEventAccess and opens the Input
Monitoring pane. It does not grant permissions, modify TCC, or guarantee macOS
will add/approve an entry after an ad-hoc signature changes. Finder reveal is the
fallback for manual addition. This authorization flow needs physical user QA;
automated tests do not exercise or dismiss system permission dialogs.

API: https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()

## Validation

The visual fixture includes General, Shortcuts, Exceptions, About and the mouse
permission recovery state, light/dark at 1x/2x, alongside switcher fixtures (36 PNGs).
Reviewed rendered layouts, including permission controls and the three-dot icon.

Final verification: 139 tests / 20 suites passed; 36 visual comparisons passed;
arm64 candidate `.build/settings-release/Altty.app` build 2026092304 passed release
verification. Includes the prior first-frame preparation fix. Running app and
`dist/` were not replaced; system permission QA remains pending on the candidate.

## Icon follow-up

The single-window icon did not convey window switching strongly enough. Replaced
it with offset overlapping windows: three titlebar dots on the front window and
only the exposed top/right outline of the rear window. Checked 18/36/108 px native
rendering in both appearances; visual comparison changed only the four About
images where this shared icon appears. Candidate build 2026092305.
