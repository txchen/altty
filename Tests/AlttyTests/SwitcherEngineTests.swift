import Testing
import Darwin
import AppKit
import Carbon
import CoreGraphics
@testable import Altty

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
        #expect(engine.send(.checkForUpdates) == [.openReleasesPage])
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
private final class ImmediateSwitchSmokeCoordinator {
    let engine: SwitcherEngine
    private let input = SystemInputAdapter()
    private let windowServer = SystemWindowServerAdapter()
    private let accessibility = SystemAccessibilityAdapter()
    private var invocationTask: Task<Void, Never>?
    private(set) var completed = false

    init(engine: SwitcherEngine) {
        self.engine = engine
    }

    func start() {
        input.install { [weak self] event in self?.receive(event) }
        input.setShortcutsEnabled(true)
    }

    func stop() {
        input.setShortcutsEnabled(false)
    }

    private func receive(_ event: ShortcutEvent) {
        switch event {
        case .allWindowsPressed:
            invocationTask = Task { [weak self] in
                guard let self else { return }
                self.run(await self.engine.beginAllWindowsSwitch())
            }
        case .holdModifiersReleased:
            let invocation = invocationTask
            invocationTask = nil
            Task { [weak self] in
                await invocation?.value
                guard let self else { return }
                self.run(self.engine.confirmAllWindowsSwitch())
            }
        }
    }

    private func run(_ effects: [SwitcherEffect]) {
        for effect in effects {
            switch effect {
            case let .deminimizeWindow(identity):
                Task { [weak self] in
                    guard let self else { return }
                    let succeeded = await self.accessibility.deminimize(identity)
                    self.run(await self.engine.receiveSwitching(
                        .deminimizeCompleted(identity, succeeded: succeeded)
                    ))
                }
            case let .focusWindow(identity):
                Task { [weak self] in
                    guard let self else { return }
                    let succeeded = await self.windowServer.focus(identity)
                    self.run(await self.engine.receiveSwitching(
                        .focusCompleted(identity, succeeded: succeeded)
                    ))
                }
            case let .verifyFocus(identity):
                Task { [weak self] in
                    guard let self else { return }
                    var observed: FocusedWindow?
                    for _ in 0..<8 {
                        try? await Task.sleep(for: .milliseconds(25))
                        observed = await self.accessibility.focusedWindow()
                        if observed == FocusedWindow(wid: identity.wid, pid: identity.pid) { break }
                    }
                    self.run(await self.engine.receiveSwitching(
                        .focusPostconditionObserved(observed)
                    ))
                }
            case .endActiveSession:
                completed = true
            default:
                break
            }
        }
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

    @Test func realImmediateSwitchTargetsTwoWindowsOwnedByTheSameApplication() async {
        guard getenv("ALTTY_RUN_FOCUS_SMOKE").map({ String(cString: $0) }) == "1" else { return }
        guard let pidText = getenv("ALTTY_FOCUS_FIXTURE_PID").map({ String(cString: $0) }),
              let pid = ProcessID(pidText),
              let widText = getenv("ALTTY_FOCUS_FIXTURE_WIDS").map({ String(cString: $0) }) else {
            Issue.record("Set ALTTY_FOCUS_FIXTURE_PID and two comma-separated ALTTY_FOCUS_FIXTURE_WIDS")
            return
        }
        let wids = widText.split(separator: ",").compactMap { WindowID($0) }
        guard wids.count == 2, wids[0] != wids[1] else {
            Issue.record("ALTTY_FOCUS_FIXTURE_WIDS must contain distinct origin,target WIDs from one application")
            return
        }

        let origin = WindowIdentity(wid: wids[0], pid: pid, generation: 1)
        let target = WindowIdentity(wid: wids[1], pid: pid, generation: 1)
        let windowServer = SystemWindowServerAdapter()
        let accessibility = SystemAccessibilityAdapter()
        guard await windowServer.focus(origin) else {
            Issue.record("Could not focus the fixture origin window")
            return
        }
        var observedOrigin: FocusedWindow?
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(25))
            observedOrigin = await accessibility.focusedWindow()
            if observedOrigin == FocusedWindow(wid: origin.wid, pid: origin.pid) { break }
        }
        guard observedOrigin == FocusedWindow(wid: origin.wid, pid: origin.pid) else {
            Issue.record("Fixture origin did not become the verified focused window")
            return
        }

        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: [
                WindowServerWindow(wid: origin.wid, pid: pid, frontToBackOrder: 0),
                WindowServerWindow(wid: target.wid, pid: pid, frontToBackOrder: 1),
            ]
        )))
        let semantics = WindowSemanticPatch(
            title: .value("Fixture"),
            role: .value("AXWindow"),
            subrole: .value("AXStandardWindow"),
            isMinimized: .value(false),
            isFullscreen: .value(false),
            isTransient: .value(false)
        )
        _ = await engine.receiveInventory(.semanticsChanged(origin, semantics))
        _ = await engine.receiveInventory(.semanticsChanged(target, semantics))
        _ = await engine.receiveInventory(.focused(origin))

        _ = NSApplication.shared
        let coordinator = ImmediateSwitchSmokeCoordinator(engine: engine)
        coordinator.start()
        guard coordinator.engine.activeSwitchSession == nil else {
            Issue.record("Smoke coordinator started with an active session")
            coordinator.stop()
            return
        }

        postKey(CGKeyCode(kVK_Option), keyDown: true, flags: .maskAlternate)
        postKey(CGKeyCode(kVK_Tab), keyDown: true, flags: .maskAlternate)
        postKey(CGKeyCode(kVK_Tab), keyDown: false, flags: .maskAlternate)
        postKey(CGKeyCode(kVK_Option), keyDown: false, flags: [])
        for _ in 0..<80 where !coordinator.completed {
            try? await Task.sleep(for: .milliseconds(25))
        }

        coordinator.stop()
        #expect(coordinator.completed)
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [target.wid, origin.wid])

        #expect(await windowServer.focus(origin))
    }

    private func postKey(_ keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else {
            Issue.record("Could not construct a synthetic keyboard event")
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

@MainActor
struct InputSmokeTests {
    @Test func realDefaultOptionTabRegistrationDoesNotChangeSystemSettings() {
        guard getenv("ALTTY_RUN_SHORTCUT_SMOKE").map({ String(cString: $0) }) == "1" else { return }
        let input = SystemInputAdapter()
        input.install { _ in }
        input.setShortcutsEnabled(true)
        #expect(input.shortcutsEnabled)
        input.setShortcutsEnabled(false)
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
struct ImmediateAllWindowsSwitchTests {
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

        #expect(await engine.beginAllWindowsSwitch() == [])
        #expect(engine.activeSwitchSession?.target.identity.wid == 10)
        #expect(engine.confirmAllWindowsSwitch() == [
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

        #expect(await engine.beginAllWindowsSwitch() == [])
        #expect(engine.confirmAllWindowsSwitch() == [.deminimizeWindow(target)])
        #expect(await engine.receiveSwitching(.deminimizeCompleted(target, succeeded: true)) == [
            .focusWindow(target),
        ])
        #expect(await engine.receiveSwitching(.focusCompleted(target, succeeded: true)) == [
            .verifyFocus(target),
        ])
        _ = await engine.receiveInventory(.focused(target))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10, 20])

        #expect(await engine.receiveSwitching(.focusPostconditionObserved(
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
        #expect(engine.confirmAllWindowsSwitch() == [.focusWindow(target)])
        #expect(await engine.receiveSwitching(.focusCompleted(target, succeeded: true)) == [
            .verifyFocus(target),
        ])
        #expect(await engine.receiveSwitching(.focusPostconditionObserved(
            FocusedWindow(wid: origin.wid, pid: origin.pid)
        )) == [
            .endActiveSession,
            .recoverFailedFocus(target: target, origin: origin),
            .presentSwitchingError(.unableToSwitch),
        ])
        #expect(engine.activeSwitchSession == nil)
        _ = await engine.receiveInventory(.focused(target))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10, 20])
        _ = await engine.receiveSwitching(.failedFocusRecoveryCompleted(target))
        _ = await engine.receiveInventory(.focused(target))
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [20, 10])
        #expect(await engine.receiveSwitching(.focusPostconditionObserved(
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
        _ = engine.confirmAllWindowsSwitch()
        #expect(await engine.receiveInventory(.destroyed(target)) == [
            .endActiveSession,
            .recoverFailedFocus(target: target, origin: origin),
            .presentSwitchingError(.unableToSwitch),
        ])
        #expect(await engine.receiveSwitching(.focusCompleted(target, succeeded: false)) == [])
        _ = await engine.receiveInventory(.focused(target))
        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10])
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
        #expect(engine.confirmAllWindowsSwitch() == [.deminimizeWindow(target)])
        #expect(await engine.receiveSwitching(.deminimizeCompleted(target, succeeded: false)) == [
            .endActiveSession,
            .recoverFailedFocus(target: target, origin: origin),
            .presentSwitchingError(.unableToSwitch),
        ])
        #expect(engine.activeSwitchSession == nil)
        #expect(await engine.inventorySnapshot().windows.map(\.wid) == [10, 20])
    }

    @Test func emptySoleCurrentAndCurrentAbsentCasesFollowTheImmediateSelectionContract() async {
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

    @Test func readinessLossCancelsAnUnconfirmedImmediateSwitch() async {
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
        #expect(engine.confirmAllWindowsSwitch() == [])
    }

    @Test func targetDestructionBeforeModifierReleaseCancelsWithoutFocusingAStaleWID() async {
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

        #expect(await engine.receiveInventory(.destroyed(target)) == [.endActiveSession])
        #expect(engine.activeSwitchSession == nil)
        #expect(engine.confirmAllWindowsSwitch() == [])
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
        )) == [
            .enrichWindows([replacement]),
            .endActiveSession,
        ])
        #expect(engine.activeSwitchSession == nil)

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
        #expect(engine.confirmAllWindowsSwitch() == [])
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
        #expect(engine.confirmAllWindowsSwitch() == [.focusWindow(target)])
    }

}
