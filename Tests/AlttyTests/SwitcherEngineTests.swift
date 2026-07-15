import Testing
import Darwin
import AppKit
import Carbon
import CoreGraphics
@testable import Altty

@MainActor
private extension SwitcherEngine {
    func receiveCurrentSwitching(
        _ event: SwitchingEvent,
        transactionID: UInt64? = nil
    ) async -> [SwitcherEffect] {
        guard let transactionID = transactionID ?? activeSwitchSession?.transactionID else {
            return []
        }
        return await receiveSwitching(event, transactionID: transactionID)
    }
}

@MainActor
struct SwitcherEngineTests {
    @Test func launchStartsUnavailableUntilBothDependenciesAreReady() {
        let engine = SwitcherEngine()

        #expect(engine.send(.launch) == [.setShortcutsEnabled(false), .checkAccessibility, .checkWindowServer])
        #expect(engine.presentationState.readinessTitle == "Checking readiness…")
        #expect(engine.receive(.accessibilityChanged(.available)) == [.recordDiagnostic(.accessibilityAvailable)])
        #expect(engine.receive(.windowServerChanged(.available)) == [
            .setShortcutsEnabled(true),
            .startInventoryObservation,
            .refreshInventory(.replace),
            .recordDiagnostic(.skyLightAvailable),
        ])
        #expect(engine.presentationState.isReady)
        #expect(engine.presentationState.readinessTitle == "Ready")
    }

    @Test func losingReadinessDisablesShortcutsAndExplainsWhy() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.receive(.accessibilityChanged(.unavailable)) == [
            .setShortcutsEnabled(false),
            .endActiveSession,
            .stopInventoryObservation,
            .clearInventory,
            .releaseAccessibilityObservers,
            .recordDiagnostic(.accessibilityUnavailable),
        ])
        #expect(engine.presentationState.readinessTitle == "Accessibility permission required")
    }

    @Test func menuCommandsExposePresentationEffects() {
        let engine = SwitcherEngine()

        #expect(engine.send(.openSettings) == [.presentSettings])
        #expect(engine.send(.requestAccessibility) == [.requestAccessibility, .checkAccessibility])
        #expect(engine.send(.checkForUpdates) == [.checkForUpdates])
        #expect(engine.send(.quit) == [.terminate])
        #expect(engine.send(.recheckReadiness) == [
            .setShortcutsEnabled(false),
            .endActiveSession,
            .stopInventoryObservation,
            .clearInventory,
            .checkAccessibility,
            .checkWindowServer,
        ])
    }

    @Test func accessibilityDenialNeverPromptsWithoutAnExplicitRequest() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.unavailable))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.send(.accessibilityStatusMayHaveChanged) == [.checkAccessibility])
        #expect(engine.send(.requestAccessibility) == [.requestAccessibility, .checkAccessibility])
    }

    @Test func runtimeAccessibilityRevocationFailsClosedAndReleasesResources() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.receive(.accessibilityChanged(.unavailable)) == [
            .setShortcutsEnabled(false),
            .endActiveSession,
            .stopInventoryObservation,
            .clearInventory,
            .releaseAccessibilityObservers,
            .recordDiagnostic(.accessibilityUnavailable),
        ])
        #expect(!engine.presentationState.isReady)
    }

    @Test func diagnosticTraceCannotCarryWindowContent() async {
        let engine = SwitcherEngine()
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [WindowServerWindow(wid: 1, pid: 10, frontToBackOrder: 0)]
        )))
        let identity = WindowIdentity(wid: 1, pid: 10, generation: 1)
        let privateContent = "trace-private-content-sentinel"
        _ = await engine.receiveInventory(.semanticsChanged(
            identity,
            WindowSemanticPatch(
                title: .value(privateContent),
                role: .value("AXWindow"),
                subrole: .value("AXStandardWindow"),
                isMinimized: .value(false),
                isFullscreen: .value(false),
                isTransient: .value(false)
            )
        ))

        let diagnostics = engine.receive(.accessibilityChanged(.unavailable)).compactMap {
            effect -> DiagnosticEvent? in
            guard case let .recordDiagnostic(event) = effect else { return nil }
            return event
        }
        #expect(diagnostics == [.accessibilityUnavailable])
        #expect(!diagnostics.map(String.init(reflecting:)).joined().contains(privateContent))
    }

    @Test func skyLightFailureRetriesOnlyForWakeOrUserRecheck() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.unavailable))

        #expect(engine.presentationState.readinessTitle == "SkyLight unsupported")
        #expect(engine.send(.accessibilityStatusMayHaveChanged) == [.checkAccessibility])
        #expect(engine.send(.systemDidWake) == [
            .setShortcutsEnabled(false),
            .endActiveSession,
            .stopInventoryObservation,
            .clearInventory,
            .checkAccessibility,
            .checkWindowServer,
        ])
        #expect(engine.presentationState.windowServer == .unknown)
    }

    @Test func permissionAndCapabilityCanRecoverWithoutRestarting() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.unavailable))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.send(.accessibilityStatusMayHaveChanged) == [.checkAccessibility])
        #expect(engine.receive(.accessibilityChanged(.available)) == [
            .setShortcutsEnabled(true),
            .startInventoryObservation,
            .refreshInventory(.replace),
            .recordDiagnostic(.accessibilityAvailable),
        ])

        _ = engine.receive(.windowServerChanged(.unavailable))
        _ = engine.send(.recheckReadiness)
        _ = engine.receive(.accessibilityChanged(.available))
        #expect(engine.receive(.windowServerChanged(.available)) == [
            .setShortcutsEnabled(true),
            .startInventoryObservation,
            .refreshInventory(.replace),
            .recordDiagnostic(.skyLightAvailable),
        ])
        #expect(engine.presentationState.isReady)
    }

    @Test func presentationDistinguishesPermissionCapabilityAndReadyStates() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.unavailable))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.presentationState.accessibilityStatusTitle == "Accessibility: Permission Required")
        #expect(engine.presentationState.showsAccessibilityAction)
        #expect(engine.presentationState.skyLightStatusTitle == "SkyLight: Ready")

        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.unavailable))
        #expect(engine.presentationState.accessibilityStatusTitle == "Accessibility: Ready")
        #expect(!engine.presentationState.showsAccessibilityAction)
        #expect(engine.presentationState.skyLightStatusTitle == "SkyLight: Unsupported")
        #expect(engine.presentationState.skyLightDetail == "Required WindowServer capability is unavailable. Altty does not use a public focus fallback.")
    }
}

@MainActor
struct WindowServerSmokeTests {
    @Test func realReadOnlySkyLightCapabilityCheck() {
        guard getenv("ALTTY_RUN_SKYLIGHT_SMOKE").map({ String(cString: $0) }) == "1" else { return }

        #expect(SystemWindowServerAdapter().availability() == .available)
    }

    @Test func realReadOnlyActiveSpaceInventoryMatchesControlledFixture() async {
        guard getenv("ALTTY_RUN_INVENTORY_SMOKE").map({ String(cString: $0) }) == "1" else { return }
        guard let pidText = getenv("ALTTY_INVENTORY_FIXTURE_PID").map({ String(cString: $0) }),
              let pid = ProcessID(pidText),
              let widText = getenv("ALTTY_INVENTORY_FIXTURE_WIDS").map({ String(cString: $0) }) else {
            Issue.record("Set ALTTY_INVENTORY_FIXTURE_PID and ALTTY_INVENTORY_FIXTURE_WIDS from the controlled fixture application")
            return
        }
        let expectedWIDs = Set(widText.split(separator: ",").compactMap { WindowID($0) })
        let snapshot = await SystemWindowServerAdapter().activeSpaceSnapshot()

        #expect(snapshot != nil)
        #expect(Set(snapshot?.windows.filter { $0.pid == pid }.map(\.wid) ?? []) == expectedWIDs)
        if let inactiveText = getenv("ALTTY_INVENTORY_INACTIVE_FIXTURE_WIDS")
            .map({ String(cString: $0) }) {
            let inactiveWIDs = Set(inactiveText.split(separator: ",").compactMap { WindowID($0) })
            let observedWIDs = Set(snapshot?.windows.map(\.wid) ?? [])
            #expect(observedWIDs.isDisjoint(with: inactiveWIDs))
        }
    }

    @Test func realImmediateAllWindowsShortcutFocusesTheNextWindow() throws {
        guard ProcessInfo.processInfo.environment["ALTTY_RUN_FOCUS_SMOKE"] == "1" else { return }
        try runFocusSmoke(
            keyCode: CGKeyCode(kVK_Tab),
            minimumWindowCount: 2,
            pressCount: 1
        )
    }

    @Test func realCurrentAppShortcutSwitchesAmongWindowsOwnedByFrontmostApplication() throws {
        guard ProcessInfo.processInfo.environment["ALTTY_RUN_CURRENT_APP_FOCUS_SMOKE"] == "1" else {
            return
        }
        try runFocusSmoke(
            keyCode: CGKeyCode(kVK_ANSI_Grave),
            minimumWindowCount: 3,
            pressCount: 2
        )
    }

    private func runFocusSmoke(
        keyCode: CGKeyCode,
        minimumWindowCount: Int,
        pressCount: Int
    ) throws {
        guard let probePath = ProcessInfo.processInfo.environment["ALTTY_FOCUS_SMOKE_PROBE"] else {
            Issue.record("ALTTY_FOCUS_SMOKE_PROBE was not built by scripts/test.sh")
            return
        }

        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: probePath)
        probe.arguments = [String(keyCode), String(minimumWindowCount), String(pressCount)]
        probe.environment = ProcessInfo.processInfo.environment
        try probe.run()
        probe.waitUntilExit()
        #expect(probe.terminationReason == .exit)
        #expect(probe.terminationStatus == 0)
    }
}

@MainActor
struct InputSmokeTests {
    @Test func escapeIsNotConsumedOutsideAnActiveSwitcherSession() {
        let input = SystemInputAdapter()
        var events: [ShortcutEvent] = []
        input.install { events.append($0) }

        #expect(!input.consumeEscapeIfActive(keyCode: UInt16(kVK_Escape)))
        #expect(events.isEmpty)
    }

    @Test func realIgnoredForegroundApplicationReceivesConfiguredShortcutPair() async throws {
        guard getenv("ALTTY_RUN_SHORTCUT_SMOKE").map({ String(cString: $0) }) == "1" else { return }
        let environment = ProcessInfo.processInfo.environment
        let probeAppURL = try #require(environment["ALTTY_SHORTCUT_PROBE_APP"].map(URL.init(fileURLWithPath:)))
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "altty-shortcut-smoke-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let outputURL = temporaryDirectory.appending(path: "received-key-codes")
        let readyURL = temporaryDirectory.appending(path: "ready")

        let input = SystemInputAdapter()
        input.install { _ in }
        #expect(input.setShortcutsEnabled(true) == .applied)
        #expect(input.shortcutsEnabled)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.environment = [
            "ALTTY_SHORTCUT_PROBE_OUTPUT": outputURL.path,
            "ALTTY_SHORTCUT_PROBE_READY": readyURL.path,
        ]
        let probe = try await NSWorkspace.shared.openApplication(
            at: probeAppURL,
            configuration: configuration
        )
        defer { probe.terminate() }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: readyURL.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: readyURL.path))
        let ignoredProbe = try #require(ExceptionRule(
            bundleIdentifier: "app.altty.shortcut-pass-through-probe",
            matchType: .exact,
            hide: false,
            ignore: .always
        ))
        let engine = SwitcherEngine(exceptionRules: [ignoredProbe])
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))
        let effects = await engine.receiveInventory(.workspaceChanged(.snapshot([
            WorkspaceApplicationFacts(
                pid: probe.processIdentifier,
                bundleIdentifier: "app.altty.shortcut-pass-through-probe",
                applicationName: "Altty Shortcut Pass-Through Probe",
                bundlePath: probeAppURL.path,
                isHidden: false,
                isFrontmost: true
            ),
        ])))
        #expect(effects == [.setShortcutsEnabled(false)])
        for effect in effects {
            if case let .setShortcutsEnabled(enabled) = effect {
                #expect(input.setShortcutsEnabled(enabled) == .applied)
            }
        }
        #expect(!input.shortcutsEnabled)
        var passedThroughKeyCodes: Set<UInt16> = []
        for _ in 0..<3_000 {
            let contents = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            passedThroughKeyCodes = Set(contents.split(separator: "\n").compactMap { UInt16($0) })
            if passedThroughKeyCodes.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(passedThroughKeyCodes == [UInt16(kVK_Tab), UInt16(kVK_ANSI_Grave)])

        let receiver = SystemInputAdapter()
        receiver.install { _ in }
        #expect(receiver.setShortcutsEnabled(true) == .applied)
        #expect(receiver.shortcutsEnabled)
        #expect(receiver.setShortcutsEnabled(false) == .applied)
    }
}

struct WindowServerTopologyTests {
    @Test func currentSpacesExcludeInactiveDesktopSpacesAndIncludePresentedFullscreenSpace() {
        let displays: [[String: Any]] = [
            [
                "Current Space": ["id64": UInt64(2), "type": 0],
                "Spaces": [
                    ["id64": UInt64(2)],
                    ["id64": UInt64(9)],
                ],
            ],
            [
                "Current Space": ["ManagedSpaceID": UInt64(7), "type": 4],
                "Spaces": [
                    ["id64": UInt64(6)],
                    ["id64": UInt64(7)],
                ],
            ],
        ]

        #expect(ManagedDisplaySpaceTopology.currentSpaceIDs(from: displays) == [2, 7])
    }
}

@MainActor
struct WindowInventoryEngineTests {
    private func semantics(
        title: String,
        minimized: Bool = false,
        transient: Bool = false
    ) -> WindowSemanticPatch {
        WindowSemanticPatch(
            title: .value(title),
            role: .value("AXWindow"),
            subrole: .value("AXStandardWindow"),
            isMinimized: .value(minimized),
            isFullscreen: .value(false),
            isTransient: .value(transient)
        )
    }

    @Test func activeSpaceSeedIsDeterministicAndQualificationRetainsHiddenOrMinimizedWindows() async {
        let engine = SwitcherEngine(inventory: WindowInventory())
        let seed = WindowServerSnapshot(
            activeSpaceIDs: [42],
            windows: [
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
                WindowServerWindow(wid: 30, pid: 300, frontToBackOrder: 0),
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 1),
            ]
        )

        #expect(await engine.receiveInventory(.replaceActiveSpace(seed)) == [
            .enrichWindows([
                WindowIdentity(wid: 30, pid: 300, generation: 1),
                WindowIdentity(wid: 10, pid: 100, generation: 1),
                WindowIdentity(wid: 20, pid: 200, generation: 1),
            ]),
        ])

        let generation: UInt64 = 1
        _ = await engine.receiveInventory(.semanticsChanged(
            WindowIdentity(wid: 30, pid: 300, generation: generation),
            semantics(title: "Minimized", minimized: true)
        ))
        _ = await engine.receiveInventory(.semanticsChanged(
            WindowIdentity(wid: 10, pid: 100, generation: generation),
            semantics(title: "Hidden application")
        ))
        _ = await engine.receiveInventory(.semanticsChanged(
            WindowIdentity(wid: 20, pid: 200, generation: generation),
            semantics(title: "Transient", transient: true)
        ))
        _ = await engine.receiveInventory(.workspaceChanged(.hidden(pid: 100, isHidden: true)))

        let snapshot = await engine.inventorySnapshot()
        #expect(snapshot.activeSpaceIDs == [42])
        #expect(snapshot.windows.map(\.wid) == [10, 30])
        #expect(snapshot.windows[0].applicationIsHidden)
        #expect(snapshot.windows[1].isMinimized)
    }

    @Test func createFocusAndDestroyUpdateMRUWithoutDuplicateEnrichment() async {
        let engine = SwitcherEngine(inventory: WindowInventory())
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [WindowServerWindow(wid: 1, pid: 10, frontToBackOrder: 0)]
        )))
        let first = WindowIdentity(wid: 1, pid: 10, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(first, semantics(title: "First")))

        let created = WindowServerWindow(wid: 2, pid: 20, frontToBackOrder: 0)
        let second = WindowIdentity(wid: 2, pid: 20, generation: 1)
        #expect(await engine.receiveInventory(.created(created, generation: 1)) == [
            .enrichWindows([second]),
        ])
        #expect(await engine.receiveInventory(.created(created, generation: 1)) == [])
        _ = await engine.receiveInventory(.semanticsChanged(second, semantics(title: "Second")))
        _ = await engine.receiveInventory(.focused(second))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [2, 1])

        _ = await engine.receiveInventory(.destroyed(second))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [1])
    }

    @Test func reusedWIDCannotInheritPriorPIDMetadataOrMRU() async {
        let engine = SwitcherEngine(inventory: WindowInventory())
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 9, pid: 90, frontToBackOrder: 0),
                WindowServerWindow(wid: 8, pid: 80, frontToBackOrder: 1),
            ]
        )))
        let old = WindowIdentity(wid: 9, pid: 90, generation: 1)
        let stable = WindowIdentity(wid: 8, pid: 80, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(old, semantics(title: "Old")))
        _ = await engine.receiveInventory(.semanticsChanged(stable, semantics(title: "Stable")))
        _ = await engine.receiveInventory(.focused(old))

        let replacementSeed = WindowServerWindow(wid: 9, pid: 99, frontToBackOrder: 0)
        let replacement = WindowIdentity(wid: 9, pid: 99, generation: 1)
        #expect(await engine.receiveInventory(.created(replacementSeed, generation: 1)) == [
            .enrichWindows([replacement]),
        ])
        _ = await engine.receiveInventory(.semanticsChanged(old, semantics(title: "Stale old event")))
        _ = await engine.receiveInventory(.focused(old))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [8])

        _ = await engine.receiveInventory(.semanticsChanged(replacement, semantics(title: "New")))
        let snapshot = await engine.inventorySnapshot()
        #expect(snapshot.windows.map(\.wid) == [8, 9])
        #expect(snapshot.windows.map(\.title) == ["Stable", "New"])
    }

    @Test func activeSpaceReplacementDropsOldGenerationAndStaleFieldsAreExplicit() async {
        let engine = SwitcherEngine(inventory: WindowInventory())
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [WindowServerWindow(wid: 1, pid: 10, frontToBackOrder: 0)]
        )))
        let old = WindowIdentity(wid: 1, pid: 10, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(old, semantics(title: "Inactive Space")))

        let replacement = WindowServerSnapshot(
            activeSpaceIDs: [2],
            windows: [WindowServerWindow(wid: 2, pid: 20, frontToBackOrder: 0)]
        )
        let current = WindowIdentity(wid: 2, pid: 20, generation: 2)
        #expect(await engine.receiveInventory(.replaceActiveSpace(replacement)) == [
            .enrichWindows([current]),
        ])
        _ = await engine.receiveInventory(.semanticsChanged(old, semantics(title: "Late old event")))
        _ = await engine.receiveInventory(.semanticsChanged(current, semantics(title: "Current")))
        _ = await engine.receiveInventory(.semanticsChanged(current, WindowSemanticPatch(title: .stale)))

        let snapshot = await engine.inventorySnapshot()
        #expect(snapshot.generation == 2)
        #expect(snapshot.activeSpaceIDs == [2])
        #expect(snapshot.windows.map(\.wid) == [2])
        #expect(snapshot.windows[0].title == "Current")
        #expect(snapshot.windows[0].titleIsStale)
    }

    @Test func reconcileUsesWindowServerAsAuthorityWithoutResettingExistingMRU() async {
        let engine = SwitcherEngine(inventory: WindowInventory())
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 1, pid: 10, frontToBackOrder: 0),
                WindowServerWindow(wid: 2, pid: 20, frontToBackOrder: 1),
            ]
        )))
        let first = WindowIdentity(wid: 1, pid: 10, generation: 1)
        let second = WindowIdentity(wid: 2, pid: 20, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(first, semantics(title: "First")))
        _ = await engine.receiveInventory(.semanticsChanged(second, semantics(title: "Second")))
        _ = await engine.receiveInventory(.focused(second))

        let third = WindowIdentity(wid: 3, pid: 30, generation: 1)
        #expect(await engine.receiveInventory(.reconcileActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 1, pid: 10, frontToBackOrder: 0),
                WindowServerWindow(wid: 3, pid: 30, frontToBackOrder: 1),
            ]
        ))) == [.enrichWindows([third])])
        _ = await engine.receiveInventory(.semanticsChanged(third, semantics(title: "Third")))

        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [1, 3])
    }

    @Test func workspaceOwnsFrontmostHiddenAndLifecycleFacts() async {
        let engine = SwitcherEngine(inventory: WindowInventory())
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 1, pid: 10, frontToBackOrder: 0),
                WindowServerWindow(wid: 2, pid: 20, frontToBackOrder: 1),
            ]
        )))
        let first = WindowIdentity(wid: 1, pid: 10, generation: 1)
        let second = WindowIdentity(wid: 2, pid: 20, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(first, semantics(title: "First")))
        _ = await engine.receiveInventory(.semanticsChanged(second, semantics(title: "Second")))
        _ = await engine.receiveInventory(.workspaceChanged(.snapshot([
            WorkspaceApplicationFacts(
                pid: 10,
                bundleIdentifier: "example.first",
                isHidden: false,
                isFrontmost: true
            ),
            WorkspaceApplicationFacts(
                pid: 20,
                bundleIdentifier: "example.second",
                isHidden: false,
                isFrontmost: false
            ),
        ])))

        _ = await engine.receiveInventory(.workspaceChanged(.activated(pid: 20)))
        _ = await engine.receiveInventory(.workspaceChanged(.hidden(pid: 20, isHidden: true)))
        _ = await engine.receiveInventory(.focused(second))
        let activated = await engine.inventorySnapshot()
        #expect(activated.windows.map(\.wid) == [2, 1])
        #expect(activated.windows[0].applicationIsFrontmost)
        #expect(activated.windows[0].applicationIsHidden)

        _ = await engine.receiveInventory(.workspaceChanged(.terminated(pid: 20)))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [1])
    }

    @Test func semanticBurstsRequestAtMostOneOutstandingAXEnrichment() async {
        let engine = SwitcherEngine(inventory: WindowInventory())
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [WindowServerWindow(wid: 1, pid: 10, frontToBackOrder: 0)]
        )))
        let identity = WindowIdentity(wid: 1, pid: 10, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(identity, semantics(title: "Initial")))

        #expect(await engine.receiveInventory(.semanticsInvalidated(identity)) == [
            .enrichWindows([identity]),
        ])
        #expect(await engine.receiveInventory(.semanticsInvalidated(identity)) == [])
        #expect(await engine.inventorySnapshot().windows.isEmpty)

        #expect(await engine.receiveInventory(.semanticsChanged(
            identity,
            semantics(title: "Superseded")
        )) == [.enrichWindows([identity])])
        #expect(await engine.inventorySnapshot().windows.isEmpty)

        _ = await engine.receiveInventory(.semanticsChanged(identity, semantics(title: "Fresh")))
        #expect(await engine.inventorySnapshot().windows.map(\.title) == ["Fresh"])
    }
}

@MainActor
private final class ManualSwitcherClock: SwitcherClock, @unchecked Sendable {
    var nowMilliseconds: Int64

    init(nowMilliseconds: Int64 = 1_000) {
        self.nowMilliseconds = nowMilliseconds
    }
}

@MainActor
struct AllWindowsSwitcherSessionTests {
    private func semantics(
        title: String,
        minimized: Bool = false,
        transient: Bool = false
    ) -> WindowSemanticPatch {
        WindowSemanticPatch(
            title: .value(title),
            role: .value("AXWindow"),
            subrole: .value("AXStandardWindow"),
            isMinimized: .value(minimized),
            isFullscreen: .value(false),
            isTransient: .value(transient)
        )
    }

    private func makeInteractiveEngine(
        clock: any SwitcherClock = SystemSwitcherClock()
    ) async -> (SwitcherEngine, [WindowIdentity]) {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory, clock: clock)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
                WindowServerWindow(wid: 30, pid: 300, frontToBackOrder: 2),
            ]
        )))
        let identities = [
            WindowIdentity(wid: 10, pid: 100, generation: 1),
            WindowIdentity(wid: 20, pid: 200, generation: 1),
            WindowIdentity(wid: 30, pid: 300, generation: 1),
        ]
        for (identity, title) in zip(identities, ["First", "Second", "Third"]) {
            _ = await engine.receiveInventory(.semanticsChanged(
                identity,
                semantics(title: title)
            ))
        }
        _ = await engine.receiveInventory(.workspaceChanged(.snapshot([
            WorkspaceApplicationFacts(
                pid: 100,
                bundleIdentifier: "example.first",
                applicationName: "First App",
                bundlePath: "/Applications/First.app",
                isHidden: false,
                isFrontmost: true
            ),
            WorkspaceApplicationFacts(
                pid: 200,
                bundleIdentifier: "example.second",
                isHidden: false,
                isFrontmost: false
            ),
            WorkspaceApplicationFacts(
                pid: 300,
                bundleIdentifier: "example.third",
                isHidden: false,
                isFrontmost: false
            ),
        ])))
        _ = await engine.receiveInventory(.focused(identities[0]))
        return (engine, identities)
    }

    @Test func heldSessionSchedulesA125MillisecondPanelWithoutFlashingForQuickTaps() async {
        let clock = ManualSwitcherClock()
        let (heldEngine, identities) = await makeInteractiveEngine(clock: clock)

        #expect(await heldEngine.beginAllWindowsSwitch() == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(heldEngine.activeSwitchSession?.mode == .allWindows)
        #expect(heldEngine.activeSwitchSession?.invocationPID == 100)
        #expect(heldEngine.activeSwitchSession?.candidates.map(\.identity) == identities)
        #expect(heldEngine.activeSwitchSession?.panelState.rows[0].applicationName == "First App")
        #expect(heldEngine.activeSwitchSession?.panelState.rows[0].applicationBundlePath == "/Applications/First.app")
        clock.nowMilliseconds += 124
        #expect(heldEngine.receiveSession(.panelDelayElapsed) == [])
        clock.nowMilliseconds += 1
        #expect(heldEngine.receiveSession(.panelDelayElapsed) == [
            .showSwitcherPanel(heldEngine.activeSwitchSession!.panelState),
        ])

        let (quickEngine, _) = await makeInteractiveEngine()
        _ = await quickEngine.beginAllWindowsSwitch()
        #expect(quickEngine.confirmSwitch() == [
            .focusWindow(WindowIdentity(wid: 20, pid: 200, generation: 1)),
        ])
        #expect(quickEngine.confirmSwitch() == [])
        #expect(quickEngine.receiveSession(.panelDelayElapsed) == [])
    }

    @Test func engineOwnsBeginVersusRepeatedNavigationPolicy() async {
        let (engine, identities) = await makeInteractiveEngine()

        #expect(await engine.invokeAllWindowsSwitch(direction: .forward) == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(engine.activeSwitchSession?.target.identity == identities[1])
        #expect(await engine.invokeAllWindowsSwitch(direction: .forward) == [])
        #expect(engine.activeSwitchSession?.target.identity == identities[2])
    }

    @Test func reverseInvocationSelectsThePreviousWindowAndWraps() async {
        let (engine, identities) = await makeInteractiveEngine()

        _ = await engine.beginAllWindowsSwitch(direction: .backward)

        #expect(engine.activeSwitchSession?.target.identity == identities[2])
        _ = engine.receiveSession(.navigate(.backward))
        #expect(engine.activeSwitchSession?.target.identity == identities[1])
    }

    @Test func keyboardAndWheelNavigationWrapWithoutPreviewingFocus() async {
        let clock = ManualSwitcherClock()
        let (engine, identities) = await makeInteractiveEngine(clock: clock)
        _ = await engine.beginAllWindowsSwitch()
        clock.nowMilliseconds += 125
        _ = engine.receiveSession(.panelDelayElapsed)

        #expect(engine.activeSwitchSession?.target.identity == identities[1])
        #expect(engine.receiveSession(.navigate(.forward)) == [
            .updateSwitcherPanel(engine.activeSwitchSession!.panelState),
        ])
        #expect(engine.activeSwitchSession?.target.identity == identities[2])
        _ = engine.receiveSession(.navigate(.forward))
        #expect(engine.activeSwitchSession?.target.identity == identities[0])
        _ = engine.receiveSession(.navigate(.backward))
        #expect(engine.activeSwitchSession?.target.identity == identities[2])
        #expect(engine.activeSwitchSession?.phase == .waitingForModifierRelease)
    }

    @Test func hoverSharesSelectionClickConfirmsAndCancellationPreservesMRU() async {
        let clickClock = ManualSwitcherClock()
        let (clickEngine, identities) = await makeInteractiveEngine(clock: clickClock)
        _ = await clickEngine.beginAllWindowsSwitch()
        clickClock.nowMilliseconds += 125
        _ = clickEngine.receiveSession(.panelDelayElapsed)

        #expect(clickEngine.receiveSession(.select(identities[2])) == [
            .updateSwitcherPanel(clickEngine.activeSwitchSession!.panelState),
        ])
        #expect(clickEngine.receiveSession(.confirm(identities[2])) == [
            .focusWindow(identities[2]),
        ])

        for reason in SwitcherCancellationReason.allCases {
            let (engine, _) = await makeInteractiveEngine()
            _ = await engine.beginAllWindowsSwitch()
            _ = engine.receiveSession(.panelDelayElapsed)
            #expect(engine.receiveSession(.cancel(reason)) == [.endActiveSession])
            #expect(engine.activeSwitchSession == nil)
            #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10, 20, 30])
        }
    }

    @Test func frozenRowsIgnoreInsertionsAndMutationsWhileDestroyedSelectionAdvances() async {
        let clock = ManualSwitcherClock()
        let (engine, identities) = await makeInteractiveEngine(clock: clock)
        _ = await engine.beginAllWindowsSwitch()
        clock.nowMilliseconds += 125
        _ = engine.receiveSession(.panelDelayElapsed)
        let capturedRows = engine.activeSwitchSession?.candidates

        let inserted = WindowIdentity(wid: 40, pid: 400, generation: 1)
        #expect(await engine.receiveInventory(.created(
            WindowServerWindow(wid: 40, pid: 400, frontToBackOrder: 0),
            generation: 1
        )) == [.enrichWindows([inserted])])
        _ = await engine.receiveInventory(.semanticsChanged(
            identities[2],
            semantics(title: "Changed", minimized: true)
        ))
        #expect(engine.activeSwitchSession?.candidates == capturedRows)

        #expect(await engine.receiveInventory(.destroyed(identities[1])) == [
            .updateSwitcherPanel(engine.activeSwitchSession!.panelState),
        ])
        #expect(engine.activeSwitchSession?.candidates.map(\.identity) == [identities[0], identities[2]])
        #expect(engine.activeSwitchSession?.target.identity == identities[2])
        #expect(engine.receiveSession(.confirm(identities[1])) == [])
        #expect(engine.activeSwitchSession?.phase == .waitingForModifierRelease)
    }


    @Test func unexpectedFrontmostApplicationChangeCancelsLostInteractionContext() async {
        let (engine, _) = await makeInteractiveEngine()
        _ = await engine.beginAllWindowsSwitch()

        #expect(await engine.receiveInventory(.workspaceChanged(.activated(pid: 999))) == [
            .endActiveSession,
        ])
        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10, 20, 30])
    }

    @Test func unexpectedFocusedWindowChangeCancelsLostInteractionContext() async {
        let (engine, identities) = await makeInteractiveEngine()
        _ = await engine.beginAllWindowsSwitch()

        #expect(await engine.receiveInventory(.focused(identities[2])) == [
            .endActiveSession,
        ])
        #expect(engine.activeSwitchSession == nil)
    }

    @Test func modifierReleaseFocusesTheWindowAfterTheCurrentMRUItemWithWraparound() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
                WindowServerWindow(wid: 30, pid: 300, frontToBackOrder: 2),
            ]
        )))
        for (wid, pid, title) in [(10, 100, "First"), (20, 200, "Second"), (30, 300, "Third")] {
            _ = await engine.receiveInventory(.semanticsChanged(
                WindowIdentity(wid: WindowID(wid), pid: ProcessID(pid), generation: 1),
                semantics(title: title)
            ))
        }
        let current = WindowIdentity(wid: 30, pid: 300, generation: 1)
        _ = await engine.receiveInventory(.focused(current))

        #expect(await engine.beginAllWindowsSwitch() == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(engine.activeSwitchSession?.target.identity.wid == 10)
        #expect(engine.confirmSwitch() == [
            .focusWindow(WindowIdentity(wid: 10, pid: 100, generation: 1)),
        ])
    }

    @Test func minimizedTargetPromotesOnlyAfterDeminimizeFocusAndExactPostcondition() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics(title: "Origin")))
        _ = await engine.receiveInventory(.semanticsChanged(
            target,
            semantics(title: "Target", minimized: true)
        ))
        _ = await engine.receiveInventory(.focused(origin))

        #expect(await engine.beginAllWindowsSwitch() == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(engine.confirmSwitch() == [.deminimizeWindow(target)])
        #expect(await engine.receiveCurrentSwitching(.deminimizeCompleted(target, succeeded: true)) == [
            .focusWindow(target),
        ])
        #expect(await engine.receiveCurrentSwitching(.focusCompleted(target, succeeded: true)) == [
            .verifyFocus(target),
        ])
        _ = await engine.receiveInventory(.focused(target))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10, 20])

        #expect(await engine.receiveCurrentSwitching(.focusPostconditionObserved(
            FocusedWindow(wid: 20, pid: 200)
        )) == [.endActiveSession])
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [20, 10])
        #expect(engine.activeSwitchSession == nil)
    }

    @Test func falseFocusSuccessRestoresOriginShowsErrorAndLeavesMRUUnchanged() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics(title: "Origin")))
        _ = await engine.receiveInventory(.semanticsChanged(target, semantics(title: "Target")))
        _ = await engine.receiveInventory(.focused(origin))

        _ = await engine.beginAllWindowsSwitch()
        #expect(engine.confirmSwitch() == [.focusWindow(target)])
        #expect(await engine.receiveCurrentSwitching(.focusCompleted(target, succeeded: true)) == [
            .verifyFocus(target),
        ])
        #expect(await engine.receiveCurrentSwitching(.focusPostconditionObserved(
            FocusedWindow(wid: origin.wid, pid: origin.pid)
        )) == [
            .endActiveSession,
            .recoverFailedFocus(target: target, origin: origin),
            .presentSwitchingError(.unableToSwitch),
        ])
        #expect(engine.activeSwitchSession == nil)
        _ = await engine.receiveInventory(.focused(target))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10, 20])
        engine.completeFailedFocusRecovery(target)
        _ = await engine.receiveInventory(.focused(target))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [20, 10])
        #expect(await engine.receiveCurrentSwitching(.focusPostconditionObserved(
            FocusedWindow(wid: target.wid, pid: target.pid)
        )) == [])
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [20, 10])
    }

    @Test func targetClosureDuringFocusFailsTheTransactionWithoutPromotingMRU() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics(title: "Origin")))
        _ = await engine.receiveInventory(.semanticsChanged(target, semantics(title: "Target")))
        _ = await engine.receiveInventory(.focused(origin))

        _ = await engine.beginAllWindowsSwitch()
        _ = engine.confirmSwitch()
        #expect(await engine.receiveInventory(.destroyed(target)) == [
            .endActiveSession,
            .recoverFailedFocus(target: target, origin: origin),
            .presentSwitchingError(.unableToSwitch),
        ])
        #expect(await engine.receiveCurrentSwitching(.focusCompleted(target, succeeded: false)) == [])
        _ = await engine.receiveInventory(.focused(target))
        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10])
    }

    @Test func titleFreeTraceRejectsLateCompletionAndFinishesTheNewerTransaction() async throws {
        let (engine, identities) = await makeInteractiveEngine()
        let target = identities[1]

        _ = await engine.beginAllWindowsSwitch()
        _ = engine.confirmSwitch()
        let firstTransaction = try #require(engine.activeSwitchSession?.transactionID)
        _ = await engine.receiveInventory(.destroyed(target))

        _ = await engine.receiveInventory(.created(
            WindowServerWindow(wid: target.wid, pid: target.pid, frontToBackOrder: 1),
            generation: target.generation
        ))
        _ = await engine.receiveInventory(.semanticsChanged(
            target,
            WindowSemanticPatch(
                role: .value("AXWindow"),
                subrole: .value("AXStandardWindow"),
                isMinimized: .value(false),
                isFullscreen: .value(false),
                isTransient: .value(false)
            )
        ))
        _ = await engine.beginAllWindowsSwitch()
        _ = engine.receiveSession(.select(target))
        _ = engine.confirmSwitch()
        let secondTransaction = try #require(engine.activeSwitchSession?.transactionID)
        let mruBeforeLateEvent = await engine.inventorySnapshot().windows.map(\.identity)
        #expect(secondTransaction != firstTransaction)

        #expect(await engine.receiveCurrentSwitching(
            .focusCompleted(target, succeeded: false),
            transactionID: firstTransaction
        ) == [])
        #expect(engine.activeSwitchSession?.transactionID == secondTransaction)
        #expect(engine.activeSwitchSession?.phase == .focusing)
        #expect(await engine.inventorySnapshot().windows.map(\.identity) == mruBeforeLateEvent)

        #expect(await engine.receiveCurrentSwitching(
            .focusCompleted(target, succeeded: true),
            transactionID: secondTransaction
        ) == [.verifyFocus(target)])
        #expect(await engine.receiveCurrentSwitching(
            .focusPostconditionObserved(FocusedWindow(wid: target.wid, pid: target.pid)),
            transactionID: secondTransaction
        ) == [.endActiveSession])
        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.inventorySnapshot().windows.first?.identity == target)
    }

    @Test func targetClosureDuringDeminimizeFailsBeforeSkyLightFocus() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics(title: "Origin")))
        _ = await engine.receiveInventory(.semanticsChanged(
            target,
            semantics(title: "Target", minimized: true)
        ))
        _ = await engine.receiveInventory(.focused(origin))

        _ = await engine.beginAllWindowsSwitch()
        #expect(engine.confirmSwitch() == [.deminimizeWindow(target)])
        #expect(await engine.receiveCurrentSwitching(.deminimizeCompleted(target, succeeded: false)) == [
            .endActiveSession,
            .recoverFailedFocus(target: target, origin: origin),
            .presentSwitchingError(.unableToSwitch),
        ])
        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10, 20])
    }

    @Test func emptySoleCurrentAndCurrentAbsentCasesFollowTheQuickSelectionContract() async {
        let emptyEngine = SwitcherEngine(inventory: WindowInventory())
        #expect(await emptyEngine.beginAllWindowsSwitch() == [])
        #expect(emptyEngine.activeSwitchSession == nil)

        let soleCurrentInventory = WindowInventory()
        let soleCurrentEngine = SwitcherEngine(inventory: soleCurrentInventory)
        _ = await soleCurrentEngine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0)]
        )))
        let soleCurrent = WindowIdentity(wid: 10, pid: 100, generation: 1)
        _ = await soleCurrentEngine.receiveInventory(.semanticsChanged(
            soleCurrent,
            semantics(title: "Only")
        ))
        _ = await soleCurrentEngine.receiveInventory(.focused(soleCurrent))
        #expect(await soleCurrentEngine.beginAllWindowsSwitch() == [])
        #expect(soleCurrentEngine.activeSwitchSession == nil)

        let absentInventory = WindowInventory()
        let absentEngine = SwitcherEngine(inventory: absentInventory)
        _ = await absentEngine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 9, pid: 90, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let absentCurrent = WindowIdentity(wid: 9, pid: 90, generation: 1)
        let onlyCandidate = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await absentEngine.receiveInventory(.semanticsChanged(
            absentCurrent,
            semantics(title: "Transient current", transient: true)
        ))
        _ = await absentEngine.receiveInventory(.semanticsChanged(
            onlyCandidate,
            semantics(title: "Only candidate")
        ))
        _ = await absentEngine.receiveInventory(.focused(absentCurrent))
        #expect(await absentEngine.beginAllWindowsSwitch() == [.focusWindow(onlyCandidate)])
        #expect(absentEngine.activeSwitchSession?.target.identity == onlyCandidate)
    }

    @Test func readinessLossCancelsAnUnconfirmedSwitcherSession() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics(title: "Origin")))
        _ = await engine.receiveInventory(.semanticsChanged(target, semantics(title: "Target")))
        _ = await engine.receiveInventory(.focused(origin))
        _ = await engine.beginAllWindowsSwitch()
        #expect(engine.activeSwitchSession != nil)

        _ = engine.receive(.accessibilityChanged(.unavailable))
        #expect(engine.activeSwitchSession == nil)
        #expect(engine.confirmSwitch() == [])
    }

    @Test func targetDestructionBeforeModifierReleaseAdvancesWithoutFocusingAStaleWID() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics(title: "Origin")))
        _ = await engine.receiveInventory(.semanticsChanged(target, semantics(title: "Target")))
        _ = await engine.receiveInventory(.focused(origin))
        _ = await engine.beginAllWindowsSwitch()

        #expect(await engine.receiveInventory(.destroyed(target)) == [])
        #expect(engine.activeSwitchSession?.target.identity == origin)
        #expect(engine.confirmSwitch() == [.focusWindow(origin)])
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10])
    }

    @Test func widReuseAndGenerationReplacementInvalidateTheCapturedSession() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics(title: "Origin")))
        _ = await engine.receiveInventory(.semanticsChanged(target, semantics(title: "Target")))
        _ = await engine.receiveInventory(.focused(origin))
        _ = await engine.beginAllWindowsSwitch()

        let replacement = WindowIdentity(wid: 20, pid: 201, generation: 1)
        #expect(await engine.receiveInventory(.created(
            WindowServerWindow(wid: 20, pid: 201, frontToBackOrder: 0),
            generation: 1
        )) == [.enrichWindows([replacement])])
        #expect(engine.activeSwitchSession?.target.identity == origin)
        #expect(engine.receiveSession(.cancel(.shortcutInterrupted)) == [.endActiveSession])

        _ = await engine.receiveInventory(.semanticsChanged(
            replacement,
            semantics(title: "Replacement")
        ))
        _ = await engine.receiveInventory(.focused(origin))
        _ = await engine.beginAllWindowsSwitch()
        let nextGeneration = WindowIdentity(wid: 30, pid: 300, generation: 2)
        #expect(await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [2],
            windows: [WindowServerWindow(wid: 30, pid: 300, frontToBackOrder: 0)]
        ))) == [
            .enrichWindows([nextGeneration]),
            .endActiveSession,
        ])
        #expect(engine.activeSwitchSession == nil)
        #expect(engine.confirmSwitch() == [])
    }

    @Test func semanticMutationWaitsUntilTheNextSession() async {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics(title: "Origin")))
        _ = await engine.receiveInventory(.semanticsChanged(target, semantics(title: "Target")))
        _ = await engine.receiveInventory(.focused(origin))
        _ = await engine.beginAllWindowsSwitch()

        #expect(await engine.receiveInventory(.semanticsInvalidated(target)) == [
            .enrichWindows([target]),
        ])
        #expect(engine.activeSwitchSession?.target.identity == target)
        #expect(engine.confirmSwitch() == [.focusWindow(target)])
    }

}

@MainActor
struct CurrentAppSwitcherSessionTests {
    private func makeEngine(
        windows: [(wid: WindowID, pid: ProcessID, transient: Bool)],
        frontmostPID: ProcessID,
        focusedWID: WindowID?,
        clock: any SwitcherClock = SystemSwitcherClock()
    ) async -> (SwitcherEngine, [WindowIdentity]) {
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory, clock: clock)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: windows.enumerated().map { index, window in
                WindowServerWindow(
                    wid: window.wid,
                    pid: window.pid,
                    frontToBackOrder: index
                )
            }
        )))
        let identities = windows.map {
            WindowIdentity(wid: $0.wid, pid: $0.pid, generation: 1)
        }
        for (identity, window) in zip(identities, windows) {
            _ = await engine.receiveInventory(.semanticsChanged(
                identity,
                WindowSemanticPatch(
                    title: .value("Window \(identity.wid)"),
                    role: .value("AXWindow"),
                    subrole: .value("AXStandardWindow"),
                    isMinimized: .value(false),
                    isFullscreen: .value(false),
                    isTransient: .value(window.transient)
                )
            ))
        }
        let pids = windows.map(\.pid).reduce(into: [ProcessID]()) { result, pid in
            if !result.contains(pid) { result.append(pid) }
        }
        _ = await engine.receiveInventory(.workspaceChanged(.snapshot(pids.map { pid in
            WorkspaceApplicationFacts(
                pid: pid,
                bundleIdentifier: "example.\(pid)",
                isHidden: false,
                isFrontmost: pid == frontmostPID
            )
        })))
        if let focusedWID,
           let focused = identities.first(where: { $0.wid == focusedWID }) {
            _ = await engine.receiveInventory(.focused(focused))
        }
        return (engine, identities)
    }

    @Test func invocationSnapshotsFrontmostPIDAndFiltersTheGlobalMRUWithoutReordering() async {
        let (engine, identities) = await makeEngine(
            windows: [
                (10, 100, false), (20, 200, false),
                (30, 100, false), (40, 200, false),
            ],
            frontmostPID: 100,
            focusedWID: 10
        )

        #expect(await engine.beginSwitch(mode: .currentApp, direction: .forward) == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(engine.activeSwitchSession?.mode == .currentApp)
        #expect(engine.activeSwitchSession?.invocationPID == 100)
        #expect(engine.activeSwitchSession?.candidates.map(\.identity) == [
            identities[0], identities[2],
        ])
        #expect(engine.activeSwitchSession?.target.identity == identities[2])
        #expect(engine.confirmSwitch() == [.focusWindow(identities[2])])
        #expect(await engine.receiveCurrentSwitching(
            .focusCompleted(identities[2], succeeded: true)
        ) == [.verifyFocus(identities[2])])
        #expect(await engine.receiveCurrentSwitching(.focusPostconditionObserved(FocusedWindow(
            wid: identities[2].wid,
            pid: identities[2].pid
        ))) == [.endActiveSession])
        #expect(await engine.inventorySnapshot().windows.map(\.identity) == [
            identities[2], identities[0], identities[1], identities[3],
        ])
    }

    @Test func alternatingModesCancelThenStartFreshSessionsWithoutMixingSnapshots() async {
        let (engine, identities) = await makeEngine(
            windows: [(10, 100, false), (20, 200, false), (30, 100, false)],
            frontmostPID: 100,
            focusedWID: 10
        )

        #expect(await engine.invokeAllWindowsSwitch(direction: .forward) == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(await engine.invokeSwitch(mode: .currentApp, direction: .forward) == [
            .endActiveSession,
        ])
        #expect(engine.activeSwitchSession == nil)

        #expect(await engine.invokeSwitch(mode: .currentApp, direction: .backward) == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(engine.activeSwitchSession?.mode == .currentApp)
        #expect(engine.activeSwitchSession?.candidates.map(\.identity) == [
            identities[0], identities[2],
        ])
        #expect(engine.activeSwitchSession?.target.identity == identities[2])

        #expect(await engine.invokeAllWindowsSwitch(direction: .forward) == [
            .endActiveSession,
        ])
        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.invokeAllWindowsSwitch(direction: .forward) == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(engine.activeSwitchSession?.mode == .allWindows)
        #expect(engine.activeSwitchSession?.candidates.map(\.identity) == identities)
    }

    @Test func frontmostApplicationChangesAfterInvocationDoNotChangeTheOwnerFilter() async {
        let (engine, identities) = await makeEngine(
            windows: [(10, 100, false), (20, 200, false), (30, 100, false)],
            frontmostPID: 100,
            focusedWID: 10
        )
        _ = await engine.beginSwitch(mode: .currentApp, direction: .forward)

        _ = await engine.receiveInventory(.workspaceChanged(.snapshot([
            WorkspaceApplicationFacts(
                pid: 100,
                bundleIdentifier: "example.100",
                isHidden: false,
                isFrontmost: false
            ),
            WorkspaceApplicationFacts(
                pid: 200,
                bundleIdentifier: "example.200",
                isHidden: false,
                isFrontmost: true
            ),
        ])))

        #expect(engine.activeSwitchSession?.invocationPID == 100)
        #expect(engine.activeSwitchSession?.candidates.map(\.identity) == [
            identities[0], identities[2],
        ])
    }

    @Test func windowlessFrontmostApplicationDoesNotBorrowThePreviousOwnersWindows() async {
        let (engine, _) = await makeEngine(
            windows: [(20, 200, false), (30, 200, false)],
            frontmostPID: 200,
            focusedWID: 20
        )
        _ = await engine.receiveInventory(.workspaceChanged(.snapshot([
            WorkspaceApplicationFacts(
                pid: 100,
                bundleIdentifier: "example.windowless",
                isHidden: false,
                isFrontmost: true
            ),
            WorkspaceApplicationFacts(
                pid: 200,
                bundleIdentifier: "example.previous",
                isHidden: false,
                isFrontmost: false
            ),
        ])))

        #expect(await engine.inventorySnapshot().frontmostApplicationPID == 100)
        #expect(await engine.beginSwitch(mode: .currentApp, direction: .forward) == [])
        #expect(engine.activeSwitchSession == nil)
    }

    @Test func committedFocusFinishesBeforeAnotherModeCanStartAFreshSession() async {
        let (engine, identities) = await makeEngine(
            windows: [(10, 100, false), (20, 200, false), (30, 200, false)],
            frontmostPID: 100,
            focusedWID: 10
        )
        _ = await engine.invokeAllWindowsSwitch(direction: .forward)
        #expect(engine.confirmSwitch() == [.focusWindow(identities[1])])

        #expect(await engine.invokeSwitch(mode: .currentApp, direction: .forward) == [])
        #expect(engine.activeSwitchSession?.mode == .allWindows)
        #expect(engine.activeSwitchSession?.phase == .focusing)
        #expect(await engine.receiveCurrentSwitching(
            .focusCompleted(identities[1], succeeded: true)
        ) == [.verifyFocus(identities[1])])
        #expect(await engine.receiveCurrentSwitching(.focusPostconditionObserved(FocusedWindow(
            wid: identities[1].wid,
            pid: identities[1].pid
        ))) == [.endActiveSession])
        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.inventorySnapshot().frontmostApplicationPID == 200)

        #expect(await engine.invokeSwitch(mode: .currentApp, direction: .forward) == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(engine.activeSwitchSession?.mode == .currentApp)
        #expect(engine.activeSwitchSession?.candidates.map(\.identity) == [
            identities[1], identities[2],
        ])
    }

    @Test func emptySoleCurrentAndSoleDifferentCasesUseTheCommonSessionContract() async {
        let emptyEngine = SwitcherEngine(inventory: WindowInventory())
        #expect(await emptyEngine.beginSwitch(mode: .currentApp, direction: .forward) == [])
        #expect(emptyEngine.activeSwitchSession == nil)

        let (soleCurrentEngine, _) = await makeEngine(
            windows: [(10, 100, false)],
            frontmostPID: 100,
            focusedWID: 10
        )
        #expect(await soleCurrentEngine.beginSwitch(mode: .currentApp, direction: .forward) == [])
        #expect(soleCurrentEngine.activeSwitchSession == nil)

        let (soleDifferentEngine, identities) = await makeEngine(
            windows: [(9, 100, true), (20, 100, false)],
            frontmostPID: 100,
            focusedWID: 9
        )
        #expect(await soleDifferentEngine.beginSwitch(mode: .currentApp, direction: .forward) == [
            .focusWindow(identities[1]),
        ])
        #expect(soleDifferentEngine.activeSwitchSession?.target.identity == identities[1])
    }

    @Test func heldCurrentAppSessionUsesSharedNavigationPanelAndExactWIDConfirmation() async {
        let clock = ManualSwitcherClock()
        let (engine, identities) = await makeEngine(
            windows: [(10, 100, false), (20, 100, false), (30, 200, false)],
            frontmostPID: 100,
            focusedWID: 10,
            clock: clock
        )

        #expect(await engine.beginSwitch(mode: .currentApp, direction: .forward) == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        clock.nowMilliseconds += 125
        #expect(engine.receiveSession(.panelDelayElapsed) == [
            .showSwitcherPanel(engine.activeSwitchSession!.panelState),
        ])
        #expect(engine.activeSwitchSession?.panelState.title == "Current App")
        #expect(engine.activeSwitchSession?.panelState.shortcutDescription == "⌥`")
        #expect(engine.activeSwitchSession?.panelState.rows.map(\.identity) == [
            identities[0], identities[1],
        ])
        #expect(engine.receiveSession(.navigate(.backward)) == [
            .updateSwitcherPanel(engine.activeSwitchSession!.panelState),
        ])
        #expect(engine.activeSwitchSession?.target.identity == identities[0])
        #expect(engine.receiveSession(.confirm(identities[1])) == [
            .focusWindow(identities[1]),
        ])
    }
}

@MainActor
struct SwitcherPanelTests {
    private func window(
        wid: WindowID,
        title: String,
        minimized: Bool = false,
        hidden: Bool = false,
        fullscreen: Bool = false
    ) -> SwitcherPanelRow {
        SwitcherPanelRow(
            identity: WindowIdentity(
                wid: wid,
                pid: ProcessID(120_000 + Int32(wid)),
                generation: 1
            ),
            title: title,
            applicationName: "example.app.\(wid)",
            applicationBundlePath: nil,
            isMinimized: minimized,
            applicationIsHidden: hidden,
            isFullscreen: fullscreen
        )
    }

    @Test func appKitPanelExposesVisibleContentSelectionAndMouseActions() {
        _ = NSApplication.shared
        let first = window(wid: 10, title: "First", minimized: true)
        let second = window(wid: 20, title: "Second", hidden: true, fullscreen: true)
        let state = SwitcherPanelState(
            mode: .allWindows,
            shortcutDescription: "⌥Tab",
            rows: [first, second],
            selectedIdentity: second.identity
        )
        let panel = SwitcherPanelController()
        var interactions: [SwitcherSessionEvent] = []
        panel.onInteraction = { interactions.append($0) }

        panel.show(state: state)
        let observed = panel.observedState
        #expect(observed.isVisible)
        #expect(observed.title == "All Windows")
        #expect(observed.shortcut == "⌥Tab")
        #expect(observed.rowCount == 2)
        #expect(observed.selectedIdentity == second.identity)
        #expect(observed.rows == [
            SwitcherPanelObservedRow(
                identity: first.identity,
                title: "First",
                applicationName: "example.app.10",
                badges: ["Minimized"],
                showsApplicationIcon: true,
                accessibilityLabel: "First, example.app.10, Minimized",
                accessibilityRole: NSAccessibility.Role.row.rawValue
            ),
            SwitcherPanelObservedRow(
                identity: second.identity,
                title: "Second",
                applicationName: "example.app.20",
                badges: ["Hidden", "Full Screen"],
                showsApplicationIcon: true,
                accessibilityLabel: "Second, example.app.20, Hidden, Full Screen",
                accessibilityRole: NSAccessibility.Role.row.rawValue
            ),
        ])
        #expect(observed.displayIdentifier != nil)
        #expect(observed.panelFrame != .zero)
        #expect(observed.visibleRowCapacity == 7)
        #expect(observed.selectedRowIsVisible)

        let firstRowLocation = panel.tableView.convert(
            NSPoint(
                x: panel.tableView.rect(ofRow: 0).midX,
                y: panel.tableView.rect(ofRow: 0).midY
            ),
            to: nil
        )
        let secondRowLocation = panel.tableView.convert(
            NSPoint(
                x: panel.tableView.rect(ofRow: 1).midX,
                y: panel.tableView.rect(ofRow: 1).midY
            ),
            to: nil
        )
        let windowNumber = panel.tableView.window?.windowNumber ?? 0
        let hoverEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: firstRowLocation,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 0,
            pressure: 0
        )!
        let clickEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: secondRowLocation,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        )!
        panel.tableView.mouseMoved(with: hoverEvent)
        panel.tableView.mouseDown(with: clickEvent)
        let scrollEvent = NSEvent(cgEvent: CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: 10,
            wheel2: 0,
            wheel3: 0
        )!)!
        panel.tableView.scrollWheel(with: scrollEvent)
        #expect(interactions == [
            .select(first.identity),
            .confirm(second.identity),
            .navigate(.backward),
        ])

        panel.dismiss()
        #expect(!panel.observedState.isVisible)
        #expect(panel.observedState.rowCount == 0)
    }

    @Test func appKitPanelVisibilityFollowsTheEngineDeadlineAndActiveSession() async {
        _ = NSApplication.shared
        let clock = ManualSwitcherClock()
        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory, clock: clock)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: 10, pid: 100, frontToBackOrder: 0),
                WindowServerWindow(wid: 20, pid: 200, frontToBackOrder: 1),
            ]
        )))
        let semantics = WindowSemanticPatch(
            title: .value("Window"),
            role: .value("AXWindow"),
            subrole: .value("AXStandardWindow"),
            isMinimized: .value(false),
            isFullscreen: .value(false),
            isTransient: .value(false)
        )
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let target = WindowIdentity(wid: 20, pid: 200, generation: 1)
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics))
        _ = await engine.receiveInventory(.semanticsChanged(target, semantics))
        _ = await engine.receiveInventory(.focused(origin))
        let panel = SwitcherPanelController()

        #expect(await engine.beginAllWindowsSwitch() == [
            .scheduleSwitcherPanel(delayMilliseconds: 125),
        ])
        #expect(!panel.observedState.isVisible)
        clock.nowMilliseconds += 124
        applyPanelEffects(engine.receiveSession(.panelDelayElapsed), to: panel)
        #expect(!panel.observedState.isVisible)
        clock.nowMilliseconds += 1
        applyPanelEffects(engine.receiveSession(.panelDelayElapsed), to: panel)
        #expect(panel.observedState.isVisible)

        applyPanelEffects(engine.receiveSession(.cancel(.escape)), to: panel)
        #expect(!panel.observedState.isVisible)
        _ = await engine.beginAllWindowsSwitch()
        applyPanelEffects(engine.receiveSession(.cancel(.outsideClick)), to: panel)
        clock.nowMilliseconds += 125
        applyPanelEffects(engine.receiveSession(.panelDelayElapsed), to: panel)
        #expect(!panel.observedState.isVisible)
    }

    private func applyPanelEffects(
        _ effects: [SwitcherEffect],
        to panel: SwitcherPanelController
    ) {
        for effect in effects {
            switch effect {
            case let .showSwitcherPanel(state):
                panel.show(state: state)
            case let .updateSwitcherPanel(state):
                panel.update(state: state)
            case .endActiveSession:
                panel.dismiss()
            default:
                break
            }
        }
    }
}
