# Domain glossary

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
