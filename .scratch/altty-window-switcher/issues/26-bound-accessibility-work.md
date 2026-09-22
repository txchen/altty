# 26 — bound accessibility work

Status: resolved

## Scope

Bound global/per-process AX work, prioritize focus and batch/resume app-window reads.

User authorized implementation of the upstream applicability report on 2026-09-22.
Implement independently within the existing Active Space/title-list architecture.
See [research](../../alttab-upstream-research/altty-applicability.md).

## Validation

Deterministic adapter/engine tests and build checks; real macOS interaction and
long-run performance must be reported separately from synthetic evidence.

## Resolution

Implemented and validated in the current working tree. See the
[implementation and validation record](../../alttab-upstream-research/implementation.md).
The complete suite passed 122 tests in 17 suites; arm64 release build, ad-hoc
app/ZIP checks, checksum and release contracts passed. Hardware interaction and
long-run resource measurements remain a separate acceptance step.
