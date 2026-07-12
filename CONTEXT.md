# Domain glossary

## Switchable Window

An individual macOS window that is eligible to appear in a switcher list. A window, rather than an application, is the fundamental selectable item.

## All-Windows Switcher

The switcher mode opened with Option-Tab. It lists Switchable Windows across applications in most-recently-used order.

## Current-App Switcher

The switcher mode opened with Option-Grave. It lists only Switchable Windows belonging to the currently active application.

## Exception Rule

A bundle-identifier-prefix rule modeled after AltTab. Its Hide behavior controls whether matching windows appear in switcher lists; its Ignore behavior controls whether global shortcuts are disabled while the matching application is frontmost. Hide and Ignore are independent behaviors, and Hide may further match window-title text.
