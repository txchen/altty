# Private adapter validation probe

This throwaway command-line probe answers a narrow question: on the current macOS/architecture, can a hardened process dynamically resolve Altty's required SkyLight discovery/focus symbols and execute read-only managed-Space/window queries without Screen Recording?

It never invokes the focus symbols. Their availability is checked, but changing window focus requires an explicit interactive validation run with postcondition observation.

Run:

```sh
sh .scratch/altty-window-switcher/validation/private-adapter-probe/run.sh
```

The build is ad-hoc signed because this machine currently has no Developer ID Application identity. A successful result does not validate Developer ID notarization, other macOS releases, TCC upgrades, Homebrew installation, or focus behavior. Altty's release scope is arm64-only; the probe's optional architecture override is retained only for diagnostic experiments.
