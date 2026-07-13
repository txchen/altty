# 21 — Build reproducible arm64 release automation

**What to build:** Create a reproducible, approval-gated release pipeline that can validate its build/package logic without production secrets and can later sign, notarize and publish the exact arm64 artifact consumed by manual download and Homebrew.

**Blocked by:** 10 — Rebuild the production App shell

**Status:** ready-for-agent

- [ ] Release builds target arm64 with macOS 15 minimum and use permanent production bundle ID `app.altty.macos`; development/test identities remain distinct.
- [ ] Tags and short versions use `MAJOR.MINOR.PATCH`; CI supplies a monotonic integer build version and names the artifact `Altty-<version>-arm64.zip`.
- [ ] Local and CI dry-run paths build/package/inspect without production secrets and fail on architecture, deployment target, identity, version or contents mismatch.
- [ ] Formal tag workflow uses an approval-protected release environment, ephemeral keychain, Developer ID Application identity and App Store Connect API-key notarization.
- [ ] The workflow enables hardened runtime and secure timestamp and rejects sandbox, `get-task-allow`, disable-library-validation and unapproved runtime-exception entitlements.
- [ ] Formal packaging signs nested code, notarizes, waits, staples, rebuilds the final ZIP and re-verifies codesign, Gatekeeper, architecture, entitlements and checksum before publication.
- [ ] A failed gate cannot create or mutate a GitHub Release or Homebrew tap update; existing version artifacts are never overwritten.
- [ ] Every release includes `checksums.txt` and release metadata tied to the exact build SHA.
- [ ] Homebrew Cask automation consumes the identical ZIP, requires arm64/macOS 15+, installs into `/Applications` and opens a tap PR changing only version, URL and SHA-256.
- [ ] Cask checks cover audit, clean install, upgrade, uninstall and explicit zap behavior without editing TCC.
- [ ] Check for Updates remains a browser action; no Sparkle framework, feed, key or background network code enters the artifact.
