# 36 — seed default exceptions

Status: resolved

## Scope

Adapt AltTab v11.7.1 default exceptions to Altty's real-window-only switchers.

## Answer

Seed fresh SettingsSnapshot.defaults with 10 fullscreen-only remote/VM shortcut
pass-through entries and one hidden McAfee Safari helper entry. Parallels matches
a bundle prefix; other entries match exactly. Omit Finder's windowless placeholder
rule, which has no equivalent in Altty. Existing persisted rules and explicit empty
lists remain untouched, including v1/v2 migrations. Invalid-settings fallback uses
the same defaults, retaining the existing diagnostic backup behavior.

Validation covers all remote entries in fullscreen and ordinary windows, exact/
prefix boundaries, Finder unaffected, helper hiding, fresh settings, edited rules,
deleted rules and legacy migration behavior. Upstream source:
https://github.com/lwouis/alt-tab-macos/blob/v11.7.1/src/preferences/Preferences.swift
