import Carbon
import Foundation
import Testing
@testable import Altty

private let hintF = ShortcutBinding(
    key: ShortcutKey(keyCode: UInt32(kVK_ANSI_F), displayName: "F"),
    modifiers: [.control, .option, .shift, .command]
)

private func general(_ hintMode: HintModeSettings) -> GeneralSettings {
    GeneralSettings(launchAtLogin: false, listPresentation: .defaults, hintMode: hintMode)
}

private func temporarySettingsURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        .appending(path: "settings.json")
}

struct HintModeSettingsPersistenceTests {
    @Test func settingsWithoutHintModeDecodeAsDisabled() throws {
        let url = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        try persistence.saveSettings(.defaults)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var generalJSON = try #require(json["general"] as? [String: Any])
        #expect(generalJSON["hintMode"] != nil)
        generalJSON["hintMode"] = nil
        json["general"] = generalJSON
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let result = persistence.loadSettings()
        #expect(result.warning == nil)
        #expect(result.snapshot.general.hintMode == .disabled)
        #expect(result.snapshot.version == SettingsSnapshot.currentVersion)
    }

    @Test func enabledHintShortcutRoundTrips() throws {
        let url = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let snapshot = SettingsSnapshot(
            shortcuts: .defaults,
            general: general(HintModeSettings(enabled: true, shortcut: hintF))
        )
        try persistence.saveSettings(snapshot)
        #expect(persistence.loadSettings() == SettingsLoadResult(snapshot: snapshot, warning: nil))

        let unbound = SettingsSnapshot(
            shortcuts: .defaults,
            general: general(HintModeSettings(enabled: true, shortcut: nil))
        )
        try persistence.saveSettings(unbound)
        #expect(persistence.loadSettings() == SettingsLoadResult(snapshot: unbound, warning: nil))
    }

    @Test func savedHintShortcutCollidingWithTheSwitcherRecoversWithAWarning() throws {
        let url = temporarySettingsURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        try persistence.saveSettings(.defaults)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var generalJSON = try #require(json["general"] as? [String: Any])
        generalJSON["hintMode"] = [
            "enabled": true,
            "shortcut": ["key": ["keyCode": kVK_Tab, "displayName": "Tab"], "modifiers": 1],
        ]
        json["general"] = generalJSON
        let invalid = try JSONSerialization.data(withJSONObject: json)
        try invalid.write(to: url)

        let result = persistence.loadSettings()
        #expect(result.warning == .invalidGeneralSettings)
        #expect(result.snapshot == .defaults)
        #expect(try Data(contentsOf: url) == invalid)
        #expect(!SettingsSnapshot(
            shortcuts: .defaults,
            general: general(HintModeSettings(enabled: false, shortcut: ShortcutPair.defaults.allWindows))
        ).isValid)
        #expect(throws: (any Error).self) {
            try persistence.saveSettings(SettingsSnapshot(
                shortcuts: .defaults,
                general: general(HintModeSettings(enabled: true, shortcut: ShortcutPair.defaults.currentApp))
            ))
        }
    }

    @Test func hintShortcutValidationRejectsSwitcherChordsAndIncompleteBindings() {
        let pair = ShortcutPair.defaults
        let tab = pair.allWindows.key
        let cases: [(ShortcutBinding, HintShortcutError?)] = [
            (pair.allWindows, .conflictsWithSwitcher),
            (pair.currentApp, .conflictsWithSwitcher),
            (ShortcutBinding(key: tab, modifiers: [.option, .shift]), .conflictsWithSwitcher),
            (ShortcutBinding(key: pair.currentApp.key, modifiers: [.option, .shift]), .conflictsWithSwitcher),
            (ShortcutBinding(key: tab, modifiers: [.shift]), .missingRequiredModifier),
            (ShortcutBinding(key: hintF.key, modifiers: []), .missingRequiredModifier),
            (ShortcutBinding(key: nil, modifiers: [.command]), .missingMainKey),
            (ShortcutBinding(key: tab, modifiers: [.command]), nil),
            (hintF, nil),
        ]
        for (binding, expected) in cases {
            #expect(HintModeSettings(enabled: true, shortcut: binding).validationError(against: pair) == expected)
        }
        #expect(HintModeSettings.disabled.validationError(against: pair) == nil)
    }
}
