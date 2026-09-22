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
