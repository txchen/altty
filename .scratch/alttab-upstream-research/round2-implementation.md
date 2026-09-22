# Four follow-up improvements — 2026-09-22

Implemented independent adaptations: read-only physical gesture ordering and serial
logical events; bounded transient AX retry; server/AX-based window qualification;
production-view pixel snapshots and a separate real hostile AppKit fixture.

Validation: 132 tests in 20 suites; 24 light/dark, 1x/2x snapshots; intentional pixel
mutation rejected; arm64 ad-hoc app build, app/ZIP verification, checksum and release
contracts passed. Release artifacts are local under .build/upstream-validation-round2.
No commit/push or installation was performed for this follow-up.

The real fixture created/closed 22 windows and exited. AX recovery failed because
AXWindows returned application-role objects (window ID error -25201); reproduced
before stalling and with a separate Objective-C app plus a standalone AX client.
The test deliberately remains failing. Do not attribute an OS cause conclusively.
See Docs/qa-fixtures.md for commands, rendering exclusions and remaining physical QA.
