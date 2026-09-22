# 31 — preserve shortcut gesture order

Status: resolved

## Scope

Pair physical shortcut presses with their own modifier releases across delayed callbacks.

Authorized by the user on 2026-09-22. Implement independently of upstream code.
See [remaining research](../../alttab-upstream-research/remaining-opportunities.md).

## Acceptance

Exercise production policy through deterministic regression tests. Keep QA controls
outside release artifacts and distinguish real system validation from simulations.

## Answer

Implemented with deterministic regression coverage; full suite passes 132 tests.
See [QA boundaries](../../../Docs/qa-fixtures.md) for physical validation still required.
