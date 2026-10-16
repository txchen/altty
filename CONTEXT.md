# Domain glossary

## Mouse Wheel Reversal

An optional, globally applied reversal of mouse scrolling relative to macOS's
current direction. It leaves trackpad scrolling alone using Scroll Reverser's
recent-touch and momentum classifier. It is independent of Switcher Sessions,
Exception Rules and SkyLight readiness, and requires Accessibility plus Input
Monitoring. There are no speed, per-device or trackpad-direction settings.

## Switchable Window

An individual macOS window on the Active Space that is eligible to appear in a switcher list. A window, rather than an application or a native tab within a window, is the fundamental selectable item.

## Active Space

The macOS Space currently presented to the user, including a fullscreen Space when it is active. Altty maintains Switchable Windows only for this Space and rebuilds its inventory when the Active Space changes.

## All-Windows Switcher

The switcher mode opened with Option-Tab. It lists Switchable Windows across applications in most-recently-used order.

## Current-App Switcher

The switcher mode opened with Option-Grave. It lists only Switchable Windows belonging to the currently active application.

## Exception Rule

A bundle-identifier rule modeled after AltTab. Its Hide behavior controls whether matching real windows appear in switcher lists; its Ignore behavior controls whether global shortcuts are disabled while the matching application is frontmost. Hide and Ignore are independent; title-based and windowless-placeholder rules do not exist in Altty.

## Switcher Session

One interaction beginning when a switcher shortcut is invoked and ending when a selection is confirmed or the interaction is cancelled. Its mode, invoking application and ordered candidate set remain stable for the session, except that invalidated windows are removed.

## Hint Mode

An optional, off-by-default keyboard alternative to clicking. It is enabled in
Settings → General and needs a user-recorded Hint Shortcut. It depends on
Accessibility only, independent of SkyLight and Switcher Sessions. Exception
Rule Ignore behavior also unregisters the Hint Shortcut.

## Hint Session

One interaction beginning when the Hint Shortcut is pressed and ending when an
action is performed or the interaction is cancelled. Its Hint Targets are
captured once by a single scan; keys typed during the scan are replayed.

## Hint Target

A clickable Accessibility element in the Hint Scope: the frontmost
application's focused window, its sheets and popovers, its top-level menu bar
items, or an open menu instead of all of these. Each has one Hint Label.

## Hint Label

The short home-row string shown on a Hint Target. Labels are prefix-free and
assigned in reading order. Typing a complete label selects its target; Return
then performs the Default Action, and modifiers choose other clicks.

## Default Action

AXPress for buttons, menu items and menu bar items, AXRaise for windows, and a
synthesized left click at the midpoint for everything else.

## Mouse Mode

An optional keyboard control for the pointer. It is off by default and requires
Accessibility and a recorded Mouse Shortcut. Exception Rule Ignore behavior
also disables the Mouse Shortcut. Hide behavior does not affect Mouse Mode.

## Mouse Session

One interaction beginning when the Mouse Shortcut is pressed. Held WASD keys
move the pointer, U selects slow speed, and I selects fast speed. Slow wins
when both speed keys are held. J and K click once per press. Clicks and changes
of frontmost application keep the Mouse Session active.

## Mouse Hints

Temporary Hint Labels within a Mouse Session, opened with F. A completed label
moves the pointer to its Hint Target and returns to stationary Mouse Mode.
Mouse Hints never perform the target's Default Action. Escape returns to Mouse
Mode, while the Mouse Shortcut ends the entire Mouse Session.
