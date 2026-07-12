Status: resolved
Type: research
Parent: ../map.md
Blocked by:

## Question

For a macOS 15+ Developer ID application distributed by notarized download and Homebrew Cask, what public and private APIs, permissions, entitlements, signing requirements, architecture requirements, and OS-version risks constrain Altty's global hotkeys, cross-application window inspection, cross-Space discovery, and window focusing?

## Answer

Resolved in [Platform and distribution constraints](../research/platform-and-distribution-constraints.md).

Altty is viable as a non-sandboxed, hardened-runtime, Developer ID-signed and notarized universal app distributed through a versioned ZIP and Homebrew Cask. Accessibility is the public permission gate for cross-app AX work and event-tap-dependent interaction. Reliable all-Space discovery and specific-WID focus have no public guarantee, so SkyLight must be an isolated, version-sensitive adapter with symbol checks, verified postconditions and an explicit degraded mode. Begin with minimal entitlements rather than inheriting AltTab's disabled library validation, and treat notarization as a security/signing check rather than private-API approval.
