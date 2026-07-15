# 21 — Build reproducible arm64 release automation

**What to build:** Create a reproducible, approval-gated release pipeline that can validate its build/package logic without production secrets and can later sign, notarize and publish the exact arm64 artifact consumed by manual download and Homebrew.

**Blocked by:** 10 — Rebuild the production App shell

**Status:** resolved

- [x] Release builds target arm64 with macOS 15 minimum and use permanent production bundle ID `app.altty.macos`; development/test identities remain distinct.
- [x] Tags and short versions use `MAJOR.MINOR.PATCH`; CI supplies a monotonic integer build version and names the artifact `Altty-<version>-arm64.zip`.
- [x] Local and CI dry-run paths build/package/inspect without production secrets and fail on architecture, deployment target, identity, version or contents mismatch.
- [x] Formal tag workflow uses an approval-protected release environment, ephemeral keychain, Developer ID Application identity and App Store Connect API-key notarization.
- [x] The workflow enables hardened runtime and secure timestamp and rejects sandbox, `get-task-allow`, disable-library-validation and unapproved runtime-exception entitlements.
- [x] Formal packaging signs nested code, notarizes, waits, staples, rebuilds the final ZIP and re-verifies codesign, Gatekeeper, architecture, entitlements and checksum before publication.
- [x] A failed gate cannot create or mutate a GitHub Release or Homebrew tap update; existing version artifacts are never overwritten.
- [x] Every release includes `checksums.txt` and release metadata tied to the exact build SHA.
- [x] Homebrew Cask automation consumes the identical ZIP, requires arm64/macOS 15+, installs into `/Applications` and opens a tap PR changing only version, URL and SHA-256.
- [x] Cask checks cover audit, clean install, upgrade, uninstall and explicit zap behavior without editing TCC.
- [x] Check for Updates remains a browser action; no Sparkle framework, feed, key or background network code enters the artifact.

## Answer

Release construction and inspection now live in reusable scripts shared by local dry runs and CI. Local builds use `app.altty.macos.dev`; release packages use the permanent production identity, semantic version, CI build number, hardened runtime, arm64-only binary and macOS 15 deployment target. Verification rejects identity/version/architecture/deployment/content/entitlement mismatches and immutable artifact overwrites.

The tag workflow is gated by the `production-release` environment, imports the Developer ID certificate into an ephemeral keychain, notarizes through an App Store Connect API key, staples and rebuilds the final ZIP, then repeats signature, Gatekeeper, architecture, entitlement and checksum checks before creating the GitHub Release. It emits build-SHA metadata and opens a narrowly scoped project-tap Cask PR. A separate manual workflow exercises Cask audit, clean install, upgrade, uninstall and zap behavior.
