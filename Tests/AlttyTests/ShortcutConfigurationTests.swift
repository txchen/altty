import Carbon
import Testing
@testable import Altty

@MainActor
struct ShortcutConfigurationTests {
    @Test func shortcutPairValidationRejectsUnsupportedBindings() {
        let optionTab = ShortcutBinding(
            key: ShortcutKey(keyCode: UInt32(kVK_Tab), displayName: "Tab"),
            modifiers: [.option]
        )
        let controlGrave = ShortcutBinding(
            key: ShortcutKey(keyCode: UInt32(kVK_ANSI_Grave), displayName: "`"),
            modifiers: [.control]
        )

        #expect(ShortcutPair(
            allWindows: ShortcutBinding(key: nil, modifiers: [.option]),
            currentApp: controlGrave
        ).validationError == .missingMainKey(.allWindows))
        #expect(ShortcutPair(
            allWindows: ShortcutBinding(key: optionTab.key, modifiers: []),
            currentApp: controlGrave
        ).validationError == .missingRequiredModifier(.allWindows))
        #expect(ShortcutPair(
            allWindows: ShortcutBinding(key: optionTab.key, modifiers: [.option, .shift]),
            currentApp: controlGrave
        ).validationError == .shiftIsReserved(.allWindows))
        #expect(ShortcutPair(
            allWindows: optionTab,
            currentApp: optionTab
        ).validationError == .duplicateBindings)
        #expect(ShortcutPair(
            allWindows: optionTab,
            currentApp: controlGrave
        ).validationError == nil)
    }

    @Test func pairReplacementKeepsEveryPreviousRegistrationWhenOneNewChordConflicts() {
        let registrar = RecordingHotKeyRegistrar()
        let input = SystemInputAdapter(registrar: registrar, usesSystemMonitors: false)
        input.install { _ in }
        #expect(input.setShortcutsEnabled(true) == .applied)
        let previousRegistrations = registrar.registrations

        let proposed = ShortcutPair(
            allWindows: ShortcutBinding(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
                modifiers: [.control]
            ),
            currentApp: ShortcutBinding(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_B), displayName: "B"),
                modifiers: [.command]
            )
        )
        registrar.unavailableKeyCode = UInt32(kVK_ANSI_B)

        #expect(input.replaceShortcuts(proposed) == .failure(.unavailableShortcut(.currentApp)))
        #expect(input.configuredShortcuts == .defaults)
        #expect(input.shortcutsEnabled)
        #expect(registrar.registrations == previousRegistrations)
    }

    @Test func successfulPairReplacementRegistersTheCompleteProposalBeforeRetiringOldBindings() {
        let registrar = RecordingHotKeyRegistrar()
        let input = SystemInputAdapter(registrar: registrar, usesSystemMonitors: false)
        input.install { _ in }
        #expect(input.setShortcutsEnabled(true) == .applied)
        let oldIDs = Set(registrar.registrations.keys)
        registrar.operations = []
        let proposed = ShortcutPair(
            allWindows: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
                modifiers: [.control]
            ),
            currentApp: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_B), displayName: "B"),
                modifiers: [.command]
            )
        )

        #expect(input.replaceShortcuts(proposed) == .applied)
        let firstUnregistration = registrar.operations.firstIndex {
            if case .unregistered = $0 { true } else { false }
        }!
        #expect(registrar.operations[..<firstUnregistration].count == 4)
        #expect(registrar.operations[..<firstUnregistration].allSatisfy {
            if case .registered = $0 { true } else { false }
        })
        #expect(Set(registrar.registrations.keys).isDisjoint(with: oldIDs))
        #expect(input.configuredShortcuts == proposed)
    }

    @Test func disablingShortcutsUnregistersEveryChordAndDoesNotConsumeLaterCallbacks() {
        let registrar = RecordingHotKeyRegistrar()
        let input = SystemInputAdapter(registrar: registrar, usesSystemMonitors: false)
        var events: [ShortcutEvent] = []
        input.install { events.append($0) }
        #expect(input.setShortcutsEnabled(true) == .applied)
        let registeredID = registrar.registrations.keys.first!

        #expect(input.setShortcutsEnabled(false) == .applied)
        #expect(registrar.registrations.isEmpty)
        #expect(!input.hotKeyPressed(id: registeredID))
        #expect(events.isEmpty)
    }

    @Test func disabledEditsRemainStagedUntilThePairCanBeRegistered() {
        let registrar = RecordingHotKeyRegistrar()
        let input = SystemInputAdapter(registrar: registrar, usesSystemMonitors: false)
        let proposed = ShortcutPair(
            allWindows: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
                modifiers: [.control]
            ),
            currentApp: ShortcutPair.defaults.currentApp
        )

        #expect(input.replaceShortcuts(proposed) == .staged)
        #expect(registrar.registrations.isEmpty)
        #expect(input.setShortcutsEnabled(true) == .applied)
        #expect(registrar.registrations.count == 4)
    }

    @Test func failedUnregistrationRemainsTrackedAndCanBeRetriedFailClosed() {
        let registrar = RecordingHotKeyRegistrar()
        let input = SystemInputAdapter(registrar: registrar, usesSystemMonitors: false)
        input.install { _ in }
        #expect(input.setShortcutsEnabled(true) == .applied)
        let previousRegistrations = registrar.registrations
        let firstOldID = previousRegistrations.keys.sorted().first!
        registrar.unregisterFailuresRemaining[firstOldID] = 1
        let proposed = ShortcutPair(
            allWindows: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
                modifiers: [.control]
            ),
            currentApp: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_B), displayName: "B"),
                modifiers: [.command]
            )
        )

        #expect(input.replaceShortcuts(proposed) == .failure(.shortcutReplacementFailed))
        #expect(input.shortcutsEnabled)
        #expect(registrar.registrations == previousRegistrations)
        #expect(input.setShortcutsEnabled(false) == .applied)
        #expect(registrar.registrations.isEmpty)
    }

    @Test func sessionConfirmsOnlyAfterEveryConfiguredModifierIsReleased() {
        let registrar = RecordingHotKeyRegistrar()
        let pair = ShortcutPair(
            allWindows: ShortcutBinding(
                key: ShortcutKey(keyCode: UInt32(kVK_Tab), displayName: "Tab"),
                modifiers: [.option, .control]
            ),
            currentApp: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_Grave), displayName: "`"),
                modifiers: [.command]
            )
        )
        let input = SystemInputAdapter(
            registrar: registrar,
            shortcuts: pair,
            usesSystemMonitors: false
        )
        var events: [ShortcutEvent] = []
        input.install { events.append($0) }
        #expect(input.setShortcutsEnabled(true) == .applied)
        let forward = registrar.registrations.values.first {
            $0.keyCode == UInt32(kVK_Tab)
                && $0.modifiers == pair.allWindows.modifiers.carbonValue
        }!

        #expect(input.hotKeyPressed(id: forward.id))
        input.modifiersChanged([.option])
        input.modifiersChanged([.control])
        #expect(events == [.switcherPressed(.allWindows, .forward)])
        input.modifiersChanged([])
        #expect(events == [
            .switcherPressed(.allWindows, .forward),
            .holdModifiersReleased,
        ])
    }

    @Test func versionedSettingsRoundTripAndMalformedInputRecoversWithoutOverwritingEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(path: "settings.json")
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let pair = ShortcutPair(
            allWindows: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
                modifiers: [.control]
            ),
            currentApp: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_B), displayName: "B"),
                modifiers: [.command]
            )
        )

        try persistence.saveSettings(SettingsSnapshot(shortcuts: pair))
        #expect(persistence.loadSettings() == SettingsLoadResult(
            snapshot: SettingsSnapshot(shortcuts: pair),
            warning: nil
        ))

        let malformed = Data("{not-json".utf8)
        try malformed.write(to: url)
        let recovered = persistence.loadSettings()
        #expect(recovered.snapshot == .defaults)
        #expect(recovered.warning == .malformed)
        #expect(try Data(contentsOf: url) == malformed)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func engineDefersAValidEditUntilTheActiveSessionEndsAndPersistsOnlyAfterRegistration() async {
        let engine = SwitcherEngine()
        let identities = [
            WindowIdentity(wid: 10, pid: 100, generation: 1),
            WindowIdentity(wid: 20, pid: 200, generation: 1),
        ]
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        for identity in identities {
            _ = await engine.receiveInventory(.semanticsChanged(
                identity,
                WindowSemanticPatch(
                    title: .value("Window"),
                    role: .value("AXWindow"),
                    subrole: .value("AXStandardWindow"),
                    isMinimized: .value(false),
                    isFullscreen: .value(false),
                    isTransient: .value(false)
                )
            ))
        }
        _ = await engine.receiveInventory(.workspaceChanged(.snapshot([
            WorkspaceApplicationFacts(
                pid: 100,
                bundleIdentifier: "example.first",
                isHidden: false,
                isFrontmost: true
            ),
            WorkspaceApplicationFacts(
                pid: 200,
                bundleIdentifier: "example.second",
                isHidden: false,
                isFrontmost: false
            ),
        ])))
        _ = await engine.receiveInventory(.focused(identities[0]))
        _ = await engine.beginAllWindowsSwitch()
        let proposedBinding = ShortcutBinding(
            key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
            modifiers: [.control, .command]
        )
        let proposedCurrentAppBinding = ShortcutBinding(
            key: ShortcutKey(keyCode: UInt32(kVK_ANSI_B), displayName: "B"),
            modifiers: [.option, .command]
        )
        let proposedPair = ShortcutPair(
            allWindows: proposedBinding,
            currentApp: proposedCurrentAppBinding
        )

        #expect(engine.send(.updateShortcut(.allWindows, proposedBinding)) == [])
        #expect(engine.send(.updateShortcut(.currentApp, proposedCurrentAppBinding)) == [])
        #expect(engine.presentationState.shortcutSettings.current == .defaults)
        #expect(engine.presentationState.shortcutSettings.pending == proposedPair)
        #expect(engine.receiveSession(.cancel(.escape)) == [
            .endActiveSession,
            .replaceShortcuts(proposedPair),
        ])
        #expect(engine.receiveShortcutRegistration(.applied(proposedPair)) == [
            .persistSettings(SettingsSnapshot(shortcuts: proposedPair)),
        ])
        #expect(engine.presentationState.shortcutSettings.current == .defaults)
        #expect(engine.presentationState.shortcutSettings.pending == proposedPair)
        #expect(engine.receiveSettingsPersistence(.saved(SettingsSnapshot(
            shortcuts: proposedPair
        ))) == [])
        #expect(engine.presentationState.shortcutSettings.current == proposedPair)
        #expect(engine.presentationState.shortcutSettings.pending == nil)
    }

    @Test func persistenceFailureRollsRegistrationBackToThePriorPair() {
        let engine = SwitcherEngine()
        let proposed = ShortcutPair(
            allWindows: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
                modifiers: [.command]
            ),
            currentApp: ShortcutPair.defaults.currentApp
        )

        #expect(engine.send(.updateShortcut(.allWindows, proposed.allWindows)) == [
            .replaceShortcuts(proposed),
        ])
        #expect(engine.receiveShortcutRegistration(.applied(proposed)) == [
            .persistSettings(SettingsSnapshot(shortcuts: proposed)),
        ])
        #expect(engine.receiveSettingsPersistence(.failed(SettingsSnapshot(
            shortcuts: proposed
        ))) == [
            .rollbackShortcuts(.defaults),
        ])
        #expect(engine.presentationState.shortcutSettings.current == .defaults)
        #expect(engine.presentationState.shortcutSettings.pending == nil)
        #expect(engine.presentationState.shortcutSettings.error == .couldNotSaveSettings)
    }

    @Test func unavailablePersistedPairRecoversToDefaultsWithAVisibleWarning() {
        let persisted = ShortcutPair(
            allWindows: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
                modifiers: [.command]
            ),
            currentApp: ShortcutPair.defaults.currentApp
        )
        let engine = SwitcherEngine(shortcuts: persisted)
        let error = ShortcutConfigurationError.unavailableShortcut(.allWindows)

        let recovered = SettingsSnapshot(shortcuts: .defaults, exceptionRules: [])
        #expect(engine.receiveShortcutRegistration(.recoveredWithDefaults(error)) == [
            .persistSettings(recovered),
        ])
        #expect(engine.receiveSettingsPersistence(.saved(recovered)) == [])
        #expect(engine.presentationState.shortcutSettings.current == .defaults)
        #expect(engine.presentationState.shortcutSettings.recoveryWarning != nil)
    }

    @Test func engineRejectsInvalidEditsAndSurfacesRegistrationConflictsInline() {
        let engine = SwitcherEngine()
        let invalid = ShortcutBinding(
            key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
            modifiers: [.shift]
        )

        #expect(engine.send(.updateShortcut(.allWindows, invalid)) == [])
        #expect(engine.presentationState.shortcutSettings.error == .shiftIsReserved(.allWindows))
        #expect(engine.presentationState.shortcutSettings.current == .defaults)

        let proposed = ShortcutPair(
            allWindows: .init(
                key: ShortcutKey(keyCode: UInt32(kVK_ANSI_A), displayName: "A"),
                modifiers: [.command]
            ),
            currentApp: ShortcutPair.defaults.currentApp
        )
        #expect(engine.send(.updateShortcut(.allWindows, proposed.allWindows)) == [
            .replaceShortcuts(proposed),
        ])
        #expect(engine.receiveShortcutRegistration(
            .failed(proposed, .unavailableShortcut(.allWindows))
        ) == [])
        #expect(engine.presentationState.shortcutSettings.current == .defaults)
        #expect(engine.presentationState.shortcutSettings.error == .unavailableShortcut(.allWindows))
    }
}

@MainActor
private final class RecordingHotKeyRegistrar: HotKeyRegistrar {
    enum Operation: Equatable {
        case registered(UInt32)
        case unregistered(UInt32)
    }

    var registrations: [UInt32: RegisteredHotKey] = [:]
    var unavailableKeyCode: UInt32?
    var operations: [Operation] = []
    var unregisterFailuresRemaining: [UInt32: Int] = [:]

    func register(_ hotKey: RegisteredHotKey) -> Bool {
        guard hotKey.keyCode != unavailableKeyCode else { return false }
        registrations[hotKey.id] = hotKey
        operations.append(.registered(hotKey.id))
        return true
    }

    func unregister(id: UInt32) -> Bool {
        if let failures = unregisterFailuresRemaining[id], failures > 0 {
            unregisterFailuresRemaining[id] = failures - 1
            return false
        }
        registrations[id] = nil
        operations.append(.unregistered(id))
        return true
    }
}
