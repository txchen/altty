Status: resolved
Type: grilling
Parent: ../map.md
Blocked by: 02, 06

## Question

What exact first-release contract should govern Developer ID signing, notarization, Apple-silicon builds, downloadable artifacts, release hosting, Homebrew Cask installation and upgrades, versioning, Check for Updates behavior, and the future seam for optional Sparkle integration?

## Comments

### 2026-07-13 — Release hosting accepted

Publish immutable versioned ZIP artifacts and release notes through GitHub Releases in the source repository. Start with a project-owned Homebrew tap and the install form `brew install --cask <owner>/tap/altty`; official `homebrew/cask` submission may follow after the product stabilizes but is not a first-release dependency. Check for Updates opens the latest GitHub Releases page and never downloads or installs inside the app.

### 2026-07-13 — Apple-silicon-only distribution accepted

Build, sign, notarize, test and publish only an `arm64` app. Intel Macs and `x86_64`/universal artifacts are outside the support contract. The Homebrew Cask declares Apple silicon compatibility and uses the single arm64 ZIP.

### 2026-07-13 — Version and artifact contract accepted

Publish only `Altty-<version>-arm64.zip`; a DMG is not part of the first release. Git tags and `CFBundleShortVersionString` use `MAJOR.MINOR.PATCH`, while CI assigns a monotonically increasing integer `CFBundleVersion`. Never replace an artifact for an existing version; issue a new patch version. Every release includes `checksums.txt` with SHA-256. The `0.x` line may evolve with explicit settings migrations; `1.0.0` begins the stable compatibility promise for settings schema and documented user behavior.

### 2026-07-13 — Signed release pipeline accepted

Only a GitHub Actions workflow triggered by a `vX.Y.Z` tag may create a formal release. Build arm64 Release with hardened runtime and secure timestamp, import the Developer ID Application identity into an ephemeral keychain, notarize through an App Store Connect API key, staple, recreate the ZIP, and verify signature policy, Gatekeeper, architecture, entitlements and checksum before publishing. Reject sandbox, `get-task-allow` and unapproved runtime-exception entitlements. Store credentials only in an approval-protected `release` environment. Local scripts may reproduce builds and checks but cannot bypass the formal gate.

### 2026-07-13 — Homebrew contract accepted

Install `Altty.app` into `/Applications`; require Apple silicon and macOS 15+ and declare no in-app auto-updates. After a GitHub Release succeeds, automation opens a tap PR changing only version, URL and SHA-256; merge requires cask audit plus install, upgrade and uninstall checks. Homebrew and manual download consume the identical notarized artifact. Keep bundle ID, Team ID and designated requirement stable across upgrades. Normal uninstall removes the app but retains Application Support settings; an explicit `zap` removes settings, cache and logs without modifying the system TCC database.

### 2026-07-13 — Manual update behavior accepted

Check for Updates in the menu and About page opens the GitHub Releases latest page in the default browser. The app performs no version API calls, launch checks, polling or background networking. Homebrew users run `brew upgrade --cask altty`; manual users replace the app themselves. Ship no Sparkle framework, feed or keys. Keep a narrow `UpdateAction` seam whose first implementation is `OpenReleasePage`; any future Sparkle integration is a separate opt-in product and security decision outside core switching state.

### 2026-07-13 — Stable release identity accepted

Choose the permanent reverse-domain bundle ID from a domain controlled by the enrolling organization before the first formal signature; do not adopt `dev.altty.app` unless that domain is controlled. The organization's Apple Developer Team owns the Developer ID identity, and the long-term maintainer controls the GitHub release environment and Homebrew tap. Keep bundle ID, Team ID and designated requirement stable. Certificate compromise or team migration is a security event that may require renewed Accessibility consent. Development, test and nightly builds use a distinct bundle ID and cannot replace or inherit the formal app's TCC identity.

### 2026-07-13 — Immutable release and recovery policy accepted

Retain every published artifact and never replace a version. Repair defects by publishing a new patch and moving the tap forward. For wrong-window focus, swallowed shortcuts, data corruption, signature or security defects, remove the affected version from latest recommendation and pause tap publication until a verified fix exists. Manual historical downloads are available but Homebrew need not manage arbitrary rollback. Release notes state supported macOS, arm64-only scope, known limitations, settings migrations and Accessibility changes. Signed/notarized `-rc.N` GitHub prereleases may use the formal identity for controlled TCC and installation validation but never update the stable tap.

## Answer

### Hosting, artifact and version identity

- GitHub Releases in the source repository is the canonical release host.
- Publish one immutable `Altty-<version>-arm64.zip` containing `Altty.app`; no DMG or universal/x86_64 artifact ships in the first release.
- Support Apple silicon on macOS 15+ only.
- Git tags and `CFBundleShortVersionString` use `MAJOR.MINOR.PATCH`; CI supplies a monotonically increasing integer `CFBundleVersion`.
- Every release includes SHA-256 in `checksums.txt`. Never overwrite an existing version; publish a patch release instead.
- `0.x` may evolve through explicit settings migrations. `1.0.0` begins the stable compatibility promise for documented behavior and settings schema.

### Signing, notarization and formal release gate

- A `vX.Y.Z` tag starts the only formal GitHub Actions release workflow, protected by manual approval on the `release` environment.
- CI imports the organization-owned Developer ID Application identity into an ephemeral keychain and notarizes with an App Store Connect API key.
- Build arm64 Release with hardened runtime and secure timestamp; reject sandbox, `get-task-allow` and unapproved runtime-exception entitlements.
- Submit, wait for notarization, staple, recreate the final ZIP, then verify `codesign`, Gatekeeper, architecture, entitlements and checksum before creating the GitHub Release.
- Local scripts reproduce builds/checks but cannot bypass the formal publishing gate.

Before the first formal signature, replace the temporary bundle ID with a permanent reverse-domain identifier controlled by the enrolling organization. Keep bundle ID, Team ID and designated requirement stable across releases. Development/test/nightly builds use separate identities. Certificate compromise or team migration is a security event and may require users to grant Accessibility again.

### Homebrew contract

- Start with a project-owned tap and install using `brew install --cask <owner>/tap/altty`; official `homebrew/cask` submission is optional after stabilization.
- The Cask requires Apple silicon and macOS 15+, installs `Altty.app` into `/Applications`, and consumes the exact notarized GitHub artifact.
- A successful stable release opens a tap PR changing only version, URL and SHA-256. Merge requires cask audit plus install, upgrade and uninstall checks.
- Normal uninstall retains Application Support settings. Explicit `zap` removes settings, cache and logs but never modifies the system TCC database.
- Homebrew upgrades move forward. Historical rollback remains a manual GitHub download, not a Cask guarantee.

### Updates and recovery

- Check for Updates in the menu and About opens the latest GitHub Releases page in the default browser.
- Altty performs no background network requests, version API calls, launch checks or downloads. Homebrew users update with `brew upgrade --cask altty`; manual users replace the app.
- Ship no Sparkle code, feed or keys. A narrow `UpdateAction` seam uses `OpenReleasePage`; future opt-in Sparkle support is a separate product/security decision.
- Releases and artifacts are immutable. Severe focus, shortcut, data, signing or security failures pause tap rollout and latest recommendation until a forward patch passes validation.
- Signed/notarized `-rc.N` prereleases may validate the formal TCC identity under controlled distribution, but never update the stable tap.
- Release notes declare supported OS, arm64-only scope, limitations, migrations and Accessibility changes.
