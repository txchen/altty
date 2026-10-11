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

@MainActor
struct CarbonHintShortcutAdapterTests {
    @Test func setShortcutConvergesAndSkipsRedundantRegistration() {
        let registrar = HintRecordingRegistrar()
        let adapter = CarbonHintShortcutAdapter(registrar: registrar, installsEventHandler: false)
        var presses = 0
        adapter.install { presses += 1 }

        #expect(adapter.setShortcut(nil))
        #expect(registrar.operations.isEmpty)
        #expect(adapter.setShortcut(hintF))
        #expect(adapter.setShortcut(hintF))
        #expect(registrar.operations == [.registered(hintF.key!.keyCode, hintF.modifiers.carbonValue)])
        #expect(adapter.hotKeyPressed(id: registrar.registeredIDs.first!))
        #expect(presses == 1)

        let other = ShortcutBinding(key: ShortcutKey(keyCode: UInt32(kVK_ANSI_J), displayName: "J"), modifiers: [.command])
        #expect(adapter.setShortcut(other))
        #expect(registrar.registeredIDs.count == 1)
        #expect(adapter.setShortcut(nil))
        #expect(adapter.setShortcut(nil))
        #expect(registrar.registeredIDs.isEmpty)
        #expect(registrar.operations.count == 4)
        #expect(!adapter.hotKeyPressed(id: 1))
        #expect(presses == 1)
    }

    @Test func registrationFailureLeavesNothingRegisteredAndRetriesLater() {
        let registrar = HintRecordingRegistrar()
        let adapter = CarbonHintShortcutAdapter(registrar: registrar, installsEventHandler: false)
        #expect(adapter.setShortcut(hintF))
        registrar.unavailableKeyCode = UInt32(kVK_ANSI_J)
        let taken = ShortcutBinding(key: ShortcutKey(keyCode: UInt32(kVK_ANSI_J), displayName: "J"), modifiers: [.command])
        #expect(!adapter.setShortcut(taken))
        #expect(registrar.registeredIDs.isEmpty)
        #expect(adapter.registeredShortcut == nil)
        #expect(!adapter.hotKeyPressed(id: 1))

        registrar.unavailableKeyCode = nil
        #expect(adapter.setShortcut(taken))
        #expect(registrar.registeredIDs.count == 1)
        #expect(!adapter.setShortcut(ShortcutBinding(key: nil, modifiers: [.command])))
        #expect(registrar.registeredIDs.isEmpty)
    }
}

@MainActor
private final class HintRecordingRegistrar: HotKeyRegistrar {
    enum Operation: Equatable {
        case registered(UInt32, UInt32)
        case unregistered(UInt32)
    }

    var unavailableKeyCode: UInt32?
    var operations: [Operation] = []
    private(set) var registeredIDs: Set<UInt32> = []

    func register(_ hotKey: RegisteredHotKey) -> Bool {
        guard hotKey.keyCode != unavailableKeyCode, !registeredIDs.contains(hotKey.id) else { return false }
        registeredIDs.insert(hotKey.id)
        operations.append(.registered(hotKey.keyCode, hotKey.modifiers))
        return true
    }

    func unregister(id: UInt32) -> Bool {
        registeredIDs.remove(id)
        operations.append(.unregistered(id))
        return true
    }
}

@MainActor
struct HintShortcutEngineTests {
    private let streamerRule = ExceptionRule(
        bundleIdentifier: "com.example.Streamer",
        matchType: .exact,
        hide: false,
        ignore: .always
    )!

    private func hintEffects(_ effects: [SwitcherEffect]) -> [ShortcutBinding?] {
        effects.compactMap { effect in
            if case let .setHintShortcut(binding) = effect { return .some(binding) }
            return nil
        }
    }

    @Test func registrationRequiresEnabledBoundAccessibleAndNotIgnoredButNotSkyLight() {
        for enabled in [true, false] {
            for shortcut in [hintF, nil] {
                for accessibility in [Availability.available, .unavailable, .unknown] {
                    for frontmost in ["com.example.Editor", "com.example.Streamer"] {
                        for windowServer in [Availability.available, .unavailable] {
                            let engine = SwitcherEngine(
                                exceptionRules: [streamerRule],
                                generalSettings: general(HintModeSettings(enabled: enabled, shortcut: shortcut))
                            )
                            #expect(hintEffects(engine.send(.launch)) == [nil])
                            var emitted = hintEffects(engine.updateFrontmostApplication(frontmost))
                            emitted += hintEffects(engine.receive(.accessibilityChanged(accessibility)))
                            emitted += hintEffects(engine.receive(.windowServerChanged(windowServer)))
                            let expected = enabled && accessibility == .available
                                && frontmost == "com.example.Editor" ? shortcut : nil
                            #expect(emitted == (expected == nil ? [] : [expected]),
                                    "enabled=\(enabled) bound=\(shortcut != nil) ax=\(accessibility) app=\(frontmost) ws=\(windowServer)")
                        }
                    }
                }
            }
        }
    }

    @Test func readinessChangesEmitOnlyWhenTheDesiredRegistrationChanges() {
        let engine = SwitcherEngine(generalSettings: general(HintModeSettings(enabled: true, shortcut: hintF)))
        _ = engine.send(.launch)
        #expect(hintEffects(engine.receive(.accessibilityChanged(.available))) == [hintF])
        #expect(hintEffects(engine.receive(.windowServerChanged(.available))) == [])
        #expect(hintEffects(engine.receive(.windowServerChanged(.unavailable))) == [])
        #expect(hintEffects(engine.send(.recheckReadiness)) == [nil])
        #expect(hintEffects(engine.receive(.accessibilityChanged(.available))) == [hintF])
        let revoked = engine.receive(.accessibilityChanged(.unavailable))
        #expect(hintEffects(revoked) == [nil])
        #expect(revoked.contains(.releaseAccessibilityObservers))
        #expect(engine.receive(.accessibilityChanged(.unavailable)) == [])
    }

    @Test func exceptionIgnoreVerdictFromInventoryTogglesTheRegistration() async {
        let engine = SwitcherEngine(
            exceptionRules: [streamerRule],
            generalSettings: general(HintModeSettings(enabled: true, shortcut: hintF))
        )
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        let streamer = WorkspaceApplicationFacts(pid: 100, bundleIdentifier: "com.example.Streamer", isHidden: false, isFrontmost: true)
        let editor = WorkspaceApplicationFacts(pid: 200, bundleIdentifier: "com.example.Editor", isHidden: false, isFrontmost: true)
        #expect(hintEffects(await engine.receiveInventory(.workspaceChanged(.snapshot([streamer])))) == [nil])
        #expect(hintEffects(await engine.receiveInventory(.workspaceChanged(.snapshot([streamer])))) == [])
        #expect(hintEffects(await engine.receiveInventory(.workspaceChanged(.snapshot([editor])))) == [hintF])
        #expect(engine.updateFrontmostApplication("com.example.Editor") == [])
        #expect(engine.updateFrontmostApplication("com.example.Streamer") == [.setHintShortcut(nil)])
    }

    @Test func settingsChangesRegisterOnlyAfterTheyPersist() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        #expect(hintEffects(engine.receive(.accessibilityChanged(.available))) == [])

        let unboundEnabled = general(HintModeSettings(enabled: true, shortcut: nil))
        let enabledSnapshot = SettingsSnapshot(shortcuts: .defaults, general: unboundEnabled)
        #expect(engine.send(.replaceGeneralSettings(unboundEnabled)) == [.persistSettings(enabledSnapshot)])
        #expect(engine.receiveSettingsPersistence(.saved(enabledSnapshot)) == [])
        #expect(engine.presentationState.generalSettings.hintModeMessage(accessibility: .available)
            == "Record a Hint shortcut in Shortcuts to start using hints.")

        let bound = SettingsSnapshot(shortcuts: .defaults, general: general(HintModeSettings(enabled: true, shortcut: hintF)))
        #expect(engine.send(.updateHintShortcut(hintF)) == [.persistSettings(bound)])
        #expect(engine.receiveSettingsPersistence(.saved(bound)) == [.setHintShortcut(hintF)])

        #expect(engine.send(.updateHintShortcut(nil)) == [.persistSettings(enabledSnapshot)])
        #expect(engine.receiveSettingsPersistence(.failed(enabledSnapshot)) == [])
        #expect(engine.presentationState.generalSettings.current.hintMode.shortcut == hintF)
        #expect(engine.presentationState.generalSettings.pending == nil)
        #expect(hintEffects(engine.receive(.windowServerChanged(.available))) == [])

        let disabled = general(HintModeSettings(enabled: false, shortcut: hintF))
        let disabledSnapshot = SettingsSnapshot(shortcuts: .defaults, general: disabled)
        #expect(engine.send(.replaceGeneralSettings(disabled)) == [.persistSettings(disabledSnapshot)])
        #expect(hintEffects(engine.receiveSettingsPersistence(.saved(disabledSnapshot))) == [nil])
        #expect(engine.presentationState.generalSettings.hintShortcutMessage
            == "Turn on keyboard hints in General to use this shortcut.")
    }

    @Test func invalidHintShortcutIsRejectedInlineWithoutPersisting() {
        let engine = SwitcherEngine(generalSettings: general(HintModeSettings(enabled: true, shortcut: hintF)))
        let reverseAllWindows = ShortcutBinding(key: ShortcutPair.defaults.allWindows.key, modifiers: [.option, .shift])
        #expect(engine.send(.updateHintShortcut(reverseAllWindows)) == [])
        #expect(engine.presentationState.generalSettings.hintShortcutError == .conflictsWithSwitcher)
        #expect(engine.presentationState.generalSettings.hintShortcutMessage == HintShortcutError.conflictsWithSwitcher.message)
        #expect(engine.presentationState.generalSettings.displayed.hintMode.shortcut == hintF)
        #expect(engine.send(.updateHintShortcut(ShortcutBinding(key: hintF.key, modifiers: [.shift]))) == [])
        #expect(engine.presentationState.generalSettings.hintShortcutError == .missingRequiredModifier)

        #expect(engine.send(.updateHintShortcut(hintF)) == [])
        #expect(engine.presentationState.generalSettings.hintShortcutError == nil)
    }

    @Test func switcherPairCannotTakeTheHintShortcutOrItsShiftVariant() {
        let hintControlF = ShortcutBinding(key: hintF.key, modifiers: [.control, .shift])
        let engine = SwitcherEngine(generalSettings: general(HintModeSettings(enabled: false, shortcut: hintControlF)))
        for binding in [hintControlF, ShortcutBinding(key: hintF.key, modifiers: [.control])] {
            let proposal = ShortcutBinding(key: binding.key, modifiers: binding.modifiers.subtracting(.shift))
            #expect(engine.send(.updateShortcut(.currentApp, proposal)) == [])
            #expect(engine.presentationState.shortcutSettings.error == .conflictsWithHintShortcut(.currentApp))
            #expect(engine.presentationState.shortcutSettings.pending == nil)
        }
        let free = ShortcutBinding(key: hintF.key, modifiers: [.command])
        #expect(engine.send(.updateShortcut(.currentApp, free)) == [
            .replaceShortcuts(ShortcutPair.defaults.replacing(.currentApp, with: free)),
        ])
    }

    @Test func registrationStatusDrivesTheUnavailableMessage() {
        let engine = SwitcherEngine(generalSettings: general(HintModeSettings(enabled: true, shortcut: hintF)))
        #expect(engine.presentationState.generalSettings.hintModeMessage(accessibility: .unavailable)
            == "Keyboard hints need Accessibility permission.")
        #expect(engine.presentationState.generalSettings.hintModeMessage(accessibility: .available) == nil)
        engine.receiveHintShortcutStatus(registered: false)
        #expect(engine.presentationState.generalSettings.hintModeMessage(accessibility: .available)
            == HintShortcutError.unavailable.message)
        #expect(engine.presentationState.generalSettings.hintShortcutMessage == HintShortcutError.unavailable.message)
        _ = engine.send(.launch)
        #expect(engine.presentationState.generalSettings.hintShortcutUnavailable)
        engine.receiveHintShortcutStatus(registered: true)
        #expect(engine.presentationState.generalSettings.hintShortcutMessage == nil)
    }
}
