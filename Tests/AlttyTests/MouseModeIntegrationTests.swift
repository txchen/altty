import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Altty

private let mouseBinding = ShortcutBinding(key: ShortcutKey(keyCode: UInt32(kVK_ANSI_M), displayName: "M"), modifiers: [.option])
private let otherBinding = ShortcutBinding(key: ShortcutKey(keyCode: UInt32(kVK_ANSI_H), displayName: "H"), modifiers: [.option])
private func mouseGeneral(enabled: Bool = true, shortcut: ShortcutBinding? = mouseBinding,
                          hint: HintModeSettings = .disabled) -> GeneralSettings {
    GeneralSettings(launchAtLogin: false, listPresentation: .defaults, hintMode: hint,
                    mouseMode: HintModeSettings(enabled: enabled, shortcut: shortcut))
}
@MainActor struct MouseModeIntegrationTests {
    @Test func oldSettingsDecodeMouseModeDisabledAndCopiesPreserveBinding() throws {
        let original = mouseGeneral()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "mouseMode")
        let decoded = try JSONDecoder().decode(GeneralSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.mouseMode == .disabled)
        #expect(original.replacingHintShortcut(otherBinding).mouseMode == original.mouseMode)
        #expect(try JSONDecoder().decode(GeneralSettings.self, from: JSONEncoder().encode(original)) == original)
    }
    @Test func conflictsAreSymmetricIncludingReverseShiftAndDisabledBindings() {
        let engine = SwitcherEngine(generalSettings: mouseGeneral(enabled: false))
        #expect(engine.send(.updateShortcut(.allWindows, mouseBinding)).isEmpty)
        #expect(engine.presentationState.shortcutSettings.error == .conflictsWithMouseShortcut(.allWindows))
        let other = SwitcherEngine(generalSettings: mouseGeneral(hint: HintModeSettings(enabled: false, shortcut: otherBinding)))
        #expect(other.send(.updateMouseShortcut(otherBinding)).isEmpty)
        #expect(other.presentationState.generalSettings.error == "Mouse and Hint shortcuts must be different.")
        #expect(other.send(.updateHintShortcut(mouseBinding)).isEmpty)
        let reverse = ShortcutBinding(key: ShortcutPair.defaults.allWindows.key, modifiers: [.option, .shift])
        #expect(mouseGeneral(shortcut: reverse).navigationValidationError(against: .defaults) != nil)
    }
    @Test func pendingSwitcherBindingAlsoBlocksMouseShortcut() {
        let engine = SwitcherEngine()
        _ = engine.send(.updateShortcut(.allWindows, mouseBinding))
        #expect(engine.send(.updateMouseShortcut(mouseBinding)).isEmpty)
        #expect(engine.presentationState.generalSettings.error != nil)
    }
    @Test func mouseRequiresAccessibilityAndIgnoreButIsIndependentOfSkyLightAndHide() {
        let ignored = ExceptionRule(bundleIdentifier: "com.example.Ignored", matchType: .exact, hide: false, ignore: .always)!
        let hidden = ExceptionRule(bundleIdentifier: "com.example.Hidden", matchType: .exact, hide: true, ignore: .none)!
        let engine = SwitcherEngine(exceptionRules: [ignored, hidden], generalSettings: mouseGeneral())
        _ = engine.send(.launch)
        #expect(engine.receive(.accessibilityChanged(.available)).contains(.setMouseShortcut(mouseBinding)))
        #expect(!engine.receive(.windowServerChanged(.unavailable)).contains(.setMouseShortcut(nil)))
        #expect(engine.updateFrontmostApplication("com.example.Ignored").contains(.setMouseShortcut(nil)))
        #expect(engine.updateFrontmostApplication("com.example.Hidden").contains(.setMouseShortcut(mouseBinding)))
        #expect(engine.receive(.accessibilityChanged(.unavailable)).contains(.setMouseShortcut(nil)))
    }
    @Test func defaultSwitcherRecoveryClearsANewlyConflictingMouseBinding() {
        let custom = ShortcutPair(allWindows: otherBinding,
                                  currentApp: ShortcutBinding(key: ShortcutKey(keyCode: 4, displayName: "H"), modifiers: [.control]))
        let settings = mouseGeneral(shortcut: ShortcutPair.defaults.allWindows)
        let engine = SwitcherEngine(shortcuts: custom, generalSettings: settings)
        let effects = engine.receiveShortcutRegistration(.recoveredWithDefaults(.shortcutReplacementFailed))
        let snapshots = effects.compactMap { effect -> SettingsSnapshot? in
            if case let .persistSettings(snapshot) = effect { return snapshot }
            return nil
        }
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.general.mouseMode.shortcut == nil)
        #expect(snapshots.first?.isValid == true)
    }
    @Test func settingsRegisterAfterPersistenceAndFailuresRemainVisible() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        let settings = mouseGeneral()
        let snapshot = SettingsSnapshot(shortcuts: .defaults, general: settings)
        #expect(engine.send(.replaceGeneralSettings(settings)) == [.persistSettings(snapshot)])
        #expect(engine.receiveSettingsPersistence(.saved(snapshot)).contains(.setMouseShortcut(mouseBinding)))
        engine.receiveMouseShortcutStatus(registered: false)
        #expect(engine.presentationState.generalSettings.mouseModeMessage(accessibility: .available) != nil)
        engine.receiveMouseShortcutStatus(registered: true)
        #expect(engine.presentationState.generalSettings.mouseModeMessage(accessibility: .available) == nil)
    }
}
