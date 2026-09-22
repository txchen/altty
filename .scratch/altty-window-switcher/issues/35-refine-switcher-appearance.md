# 35 — refine switcher appearance

Status: resolved

## Scope

Keep both switch modes visually consistent, including existing headings and repeated
application names. Refine selection styling, outer spacing and density proportions.

## Answer

Use translucent system accent fill with an accent outline and normal text contrast.
Increase outline/fill contrast when macOS Increase Contrast is enabled. Add 8-point
horizontal gutters and 10-point bottom padding. Comfortable density pairs its existing
60-point row height with 36-point icons and 14/12-point title/subtitle text; compact
retains 52-point rows, 32-point icons and 13/11-point text. Rebuild row content when
density changes so the sizes take effect immediately.

Validation: 132 existing tests passed. Reviewed short, CJK, scrolled and removed-row
snapshots in light/dark appearances and updated the affected visual baselines.
