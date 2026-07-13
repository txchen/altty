# 22 — Validate and publish the first signed release candidate

**What to build:** Validate the completed application under the permanent organization identity and promote a fully passing signed/notarized release candidate to the first stable GitHub and Homebrew release. Every claim is linked to the exact build SHA and failures prevent publication.

**Blocked by:** 08 — Validate private adapter and permission lifecycle; 20 — Meet the lightweight performance budget; 21 — Build reproducible arm64 release automation

**Status:** ready-for-agent

- [ ] `app.altty.macos` is registered under the intended organization Team and the RC uses the expected Developer ID identity and designated requirement.
- [ ] The final arm64/macOS 15 artifact passes nested signature verification, hardened-runtime/entitlement policy, secure timestamp, notarization, staple and Gatekeeper.
- [ ] The final ZIP is revalidated after packaging, launched through a real quarantine-origin download and matches GitHub/Cask/checksum metadata.
- [ ] Accessibility lifecycle passes clean grant, denial/retry, runtime revoke/regrant, signed upgrade and app-movement cases without requiring an app restart for normal recovery.
- [ ] Direct ZIP, Homebrew clean install, upgrade, cross-replacement, uninstall and zap pass while preserving or removing settings according to contract and never editing TCC.
- [ ] SkyLight read-only capability and explicitly initiated exact-WID focus pass on each advertised macOS major, an M1 baseline and a newer supported Apple-silicon Mac.
- [ ] The compatibility matrix covers normal, minimized, hidden, same-app multi-window and fullscreen Active Space behavior, multiple displays, Stage Manager, supported keyboard layouts and representative native/Electron/nonstandard applications.
- [ ] The functional, failure/race and lightweight performance suites pass and publish evidence linked to the RC build SHA.
- [ ] About/version/project/update information, release notes, arm64-only support statement, known limitations and settings/Accessibility migration notes agree with the artifact.
- [ ] The artifact contains no tests, debug symbols, credentials, CI residue or user-content diagnostics.
- [ ] A failed criterion blocks stable GitHub Release and tap publication; a passing `-rc.N` is promoted through an immutable stable version and forward-fix policy.
