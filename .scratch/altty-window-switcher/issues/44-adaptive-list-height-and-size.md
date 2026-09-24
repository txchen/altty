# 44 — adaptive list height and size

Status: resolved

## User request and upstream evidence

Follow AltTab's list-view sizing behavior and expose only sizing controls that
AltTab itself has. Local upstream v11.7.1: `Appearance.titlesSize` defines text/icon
sizes; `Appearance.maxHeightOnScreen` is 0.8; `TilesPanel.maxThumbnailsHeight`
and `TilesView.layoutParentViews` also apply that cap to titles mode. Its
appearance size control offers Small, Medium, Large and Auto. Auto tries sizes
largest first, then scrolls if even Small cannot fit. There is no fixed visible
row-count preference in that current UI. This is behavioral reference only;
Altty's implementation, two-line rows and assets remain independent.

## Implementation

Removed the 6/7/8-row limit and Compact/Comfortable controls. General → Window
list now offers Size: Small, Medium, Large, Auto. New settings default to Auto.
Both switcher modes grow to fit their content, capped at 80% of the chosen
screen height and at the usable screen height. Complete rows are preferred;
excess windows scroll and the selection stays visible. Auto uses the largest
size fitting all rows, falling back to Small plus scrolling. Selection-only
changes never alter size or panel geometry.

Settings schema five writes only `size`. Earlier density preferences migrate
Compact → Small and Comfortable → Medium; the obsolete row count is ignored.
Other settings, including diagnostic logging, are preserved.

## Validation

150 tests pass, including Auto thresholds, manual-size stability, usable screen
bounds, legacy settings migration, small secondary-screen placement, selected
last-row visibility, and 100 first-frame render iterations. 36 visual fixtures
pass after inspection and baseline updates for the intended geometry/size changes.
Build 2026092309 includes this feature and the diagnostic logging setting.
