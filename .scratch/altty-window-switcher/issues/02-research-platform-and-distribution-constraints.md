Status: resolved
Type: research
Parent: ../map.md
Blocked by:

## Question

For a macOS 15+ Developer ID application distributed by notarized download and Homebrew Cask, what public and private APIs, permissions, entitlements, signing requirements, architecture requirements, and OS-version risks constrain Altty's global hotkeys, cross-application window inspection, cross-Space discovery, and window focusing?

## Answer

Resolved in [Platform and distribution constraints](../research/platform-and-distribution-constraints.md).

Altty is viable as a non-sandboxed, hardened-runtime, Developer ID-signed and notarized app distributed through a versioned ZIP and Homebrew Cask. Accessibility is the public permission gate for cross-app AX work and event-tap-dependent interaction. Reliable all-Space discovery and specific-WID focus have no public guarantee, so SkyLight must be an isolated, version-sensitive adapter with symbol checks and verified postconditions. Begin with minimal entitlements rather than inheriting AltTab's disabled library validation, and treat notarization as a security/signing check rather than private-API approval.

The original degraded-mode recommendation was superseded during [Choose technical architecture](06-choose-technical-architecture.md): Altty limits discovery to the Active Space, uses SkyLight as its sole focus path and disables switching if that capability is unavailable.

The original universal-build recommendation was superseded during [Define release and update contract](07-define-release-and-update-contract.md): Altty supports and publishes Apple silicon (`arm64`) only.
