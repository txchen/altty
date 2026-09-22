# Upstream-inspired improvements implemented — 2026-09-22

Implemented the five production work packages and the regression package from
[the applicability report](altty-applicability.md). All new implementation is
independent; no AltTab source was copied. Existing mouse-reversal work and other
working-tree edits were retained. Base HEAD is
`a9efa07154451dd4dee596d3a1fe16a1650ce3ee`; validation applies to the current dirty
working tree, not to that commit alone.

## Delivered

1. **Active Space boundary:** immediate engine invalidation and session cancellation;
   invocations awaiting snapshots and queued shortcut press/release callbacks cannot
   cross the boundary. New invocations are ignored until a current replacement is
   accepted. Old focus completions cannot advance a new transaction. An OS focus
   call already running cannot be forcibly undone.
2. **AX query scheduling:** bounded Dispatch execution, four global query slots,
   one per PID, at most three background jobs; interactive focus has priority and
   reserved global capacity. Process groups share a single AX window enumeration.
   Traversal resumes across 250 ms elapsed-time slices and publishes each slice's
   results. Remaining slice time bounds individual requested IPC timeouts.
3. **Refresh progress:** one physical snapshot query, one merged follow-up and a
   fixed 75 ms coalescing window. Continuous ordinary events cannot perpetually
   reset the deadline. Space/monitoring revisions reject obsolete completions.
   Stopping invalidates work without falsely freeing a physical query slot.
   Semantic invalidations likewise use a fixed window and the existing per-window
   one-in-flight/dirty-follow-up policy.
4. **Process lifecycle:** kernel liveness checks at admission and before/after
   observer registration; stable notification-source identity survives missing
   PIDs and distinguishes obsolete termination after PID reuse. Termination drops
   queued queries and rejects running results; observer callbacks remain tokened.
5. **Incremental panel updates:** selection-only changes reuse views; content changes
   reload affected rows; structure or preferences trigger layout. Actions continue
   to resolve by window identity.
6. **Regression coverage:** ten new tests cover blocked query fairness, cancellation,
   1,000 queued refresh events, delayed answers across replacement/restart,
   enumeration once with resumable reads, registration-time exit, Space boundaries,
   stable PID identity and 200 selection-only updates with view reuse. Existing
   tests cover refused/false-success focus, late transactions, 1,000 window
   lifecycles and 100 verified switches.

## Validation

- `ALTTY_SWIFT_BUILD_SYSTEM=native scripts/test.sh`: **122 tests / 17 suites passed**.
- Release arm64 build: passed, using isolated `.build/upstream-validation/Altty.app`.
- `scripts/finalize-release.sh`: app and ZIP checks, ad-hoc hardened signature,
  bundle contents, architecture/deployment target and SHA-256 verification passed.
- `ruby scripts/test-release-contract.rb`: passed.
- `git diff --check`: passed.
- Logs: `test-final.log`, `build-validation.log`, `package-validation.log` in this
  directory (local, ignored). The native Swift build option emits its existing
  deprecation warning; there were no source compilation warnings/errors.

The validation ZIP is `.build/upstream-validation/artifacts/Altty-0.0.0-arm64.zip`
(build 2026092201). It is an ad-hoc test artifact, not a notarized release. Nothing
was installed, published or enabled in the user's live input settings.

## Remaining hardware acceptance

These are deterministic/synthetic and packaging checks. Actual macOS Space
transition interaction, stalled real AX providers, clean-hardware CPU/RSS and
long-run process churn remain unmeasured. See [performance procedure](../../Docs/performance.md).
No claim is made that the automated timings predict production CPU/memory gains.
