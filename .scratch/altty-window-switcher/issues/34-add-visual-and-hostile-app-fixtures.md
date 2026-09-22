# 34 — add visual and hostile app fixtures

Status: claimed

## Scope

Add rendered UI baselines and a disposable real macOS app supporting controlled stalls and window churn.

Authorized by the user on 2026-09-22. Implement independently of upstream code.
See [remaining research](../../alttab-upstream-research/remaining-opportunities.md).

## Acceptance

Exercise production policy through deterministic regression tests. Keep QA controls
outside release artifacts and distinguish real system validation from simulations.

## Progress

Implemented 24 reviewed pixel baselines, a failing-diff comparator and a real AppKit
stall/churn fixture. Pixel checks and 22-window lifecycle passed. AX integration
remains failing on this macOS 27 host: returned window elements have AXApplication
role even in an independent minimal Objective-C repro. Do not close the real AX
acceptance gate from mocked test results. See [QA details](../../../Docs/qa-fixtures.md).
