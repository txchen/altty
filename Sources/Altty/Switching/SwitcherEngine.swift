import Foundation

enum Availability: Equatable, Sendable {
    case unknown
    case unavailable
    case available
}

struct SwitcherPresentationState: Equatable, Sendable {
    private struct DependencyDescription {
        let statusTitle: String
        let detail: String
    }

    let hasLaunched: Bool
    let accessibility: Availability
    let windowServer: Availability
    var shortcutSettings = ShortcutSettingsState(
        current: .defaults,
        pending: nil,
        error: nil,
        recoveryWarning: nil
    )

    var isReady: Bool { accessibility == .available && windowServer == .available }

    var readinessTitle: String {
        if isReady { return "Ready" }
        if accessibility == .unavailable { return "Accessibility permission required" }
        if windowServer == .unavailable { return "SkyLight unsupported" }
        return hasLaunched ? "Checking readiness…" : "Starting…"
    }

    private var accessibilityDescription: DependencyDescription {
        switch accessibility {
        case .unknown:
            DependencyDescription(
                statusTitle: "Accessibility: Checking…",
                detail: "Checking whether Altty can read and prepare windows for switching."
            )
        case .unavailable:
            DependencyDescription(
                statusTitle: "Accessibility: Permission Required",
                detail: "Allow Altty in Privacy & Security so it can read and prepare windows for switching."
            )
        case .available:
            DependencyDescription(
                statusTitle: "Accessibility: Ready",
                detail: "Altty has the required Accessibility permission."
            )
        }
    }

    var accessibilityStatusTitle: String { accessibilityDescription.statusTitle }
    var accessibilityDetail: String { accessibilityDescription.detail }

    var showsAccessibilityAction: Bool { accessibility == .unavailable }

    private var skyLightDescription: DependencyDescription {
        switch windowServer {
        case .unknown:
            DependencyDescription(
                statusTitle: "SkyLight: Checking…",
                detail: "Checking the required WindowServer capability."
            )
        case .unavailable:
            DependencyDescription(
                statusTitle: "SkyLight: Unsupported",
                detail: "Required WindowServer capability is unavailable. Altty does not use a public focus fallback."
            )
        case .available:
            DependencyDescription(
                statusTitle: "SkyLight: Ready",
                detail: "The required WindowServer capability is available."
            )
        }
    }

    var skyLightStatusTitle: String { skyLightDescription.statusTitle }
    var skyLightDetail: String { skyLightDescription.detail }
}

enum SwitcherCommand: Equatable, Sendable {
    case launch
    case accessibilityStatusMayHaveChanged
    case systemDidWake
    case openSettings
    case requestAccessibility
    case checkForUpdates
    case quit
    case recheckReadiness
    case updateShortcut(SwitcherMode, ShortcutBinding)
}

enum SwitcherEvent: Equatable, Sendable {
    case accessibilityChanged(Availability)
    case windowServerChanged(Availability)
}

enum InventoryRefreshMode: Equatable, Sendable {
    case replace
    case reconcile
}

enum SwitcherEffect: Equatable, Sendable {
    case checkAccessibility
    case checkWindowServer
    case setShortcutsEnabled(Bool)
    case endActiveSession
    case releaseAccessibilityObservers
    case recordDiagnostic(DiagnosticEvent)
    case presentSettings
    case requestAccessibility
    case openReleasesPage
    case terminate
    case enrichWindows([WindowIdentity])
    case startInventoryObservation
    case stopInventoryObservation
    case refreshInventory(InventoryRefreshMode)
    case clearInventory
    case focusWindow(WindowIdentity)
    case deminimizeWindow(WindowIdentity)
    case verifyFocus(WindowIdentity)
    case recoverFailedFocus(target: WindowIdentity, origin: WindowIdentity?)
    case presentSwitchingError(SwitchingError)
    case scheduleSwitcherPanel(delayMilliseconds: Int)
    case showSwitcherPanel(SwitcherPanelState)
    case updateSwitcherPanel(SwitcherPanelState)
    case replaceShortcuts(ShortcutPair)
    case persistSettings(SettingsSnapshot)
}

enum SwitchingError: Equatable, Sendable {
    case unableToSwitch
}

enum SwitcherMode: Equatable, Sendable {
    case allWindows
    case currentApp

    var title: String {
        switch self {
        case .allWindows: "All Windows"
        case .currentApp: "Current App"
        }
    }
}

enum SwitchDirection: Equatable, Sendable {
    case forward
    case backward
}

enum SwitcherCancellationReason: CaseIterable, Equatable, Sendable {
    case escape
    case outsideClick
    case lostInteractionContext
    case shortcutInterrupted
}

enum SwitcherSessionEvent: Equatable, Sendable {
    case panelDelayElapsed
    case navigate(SwitchDirection)
    case select(WindowIdentity)
    case confirm(WindowIdentity?)
    case cancel(SwitcherCancellationReason)
}

@MainActor
protocol SwitcherClock: Sendable {
    var nowMilliseconds: Int64 { get }
}

struct SystemSwitcherClock: SwitcherClock {
    var nowMilliseconds: Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1_000)
    }
}

struct SwitcherPanelState: Equatable, Sendable {
    let mode: SwitcherMode
    let shortcutDescription: String
    let rows: [SwitcherPanelRow]
    let selectedIdentity: WindowIdentity

    var title: String { mode.title }
}

struct SwitcherPanelRow: Equatable, Sendable {
    let identity: WindowIdentity
    let title: String
    let applicationName: String
    let applicationBundlePath: String?
    let isMinimized: Bool
    let applicationIsHidden: Bool
    let isFullscreen: Bool
}

enum SwitcherSessionPhase: Equatable, Sendable {
    case waitingForModifierRelease
    case deminimizing
    case focusing
    case verifying
}

struct SwitcherSession: Equatable, Sendable {
    let mode: SwitcherMode
    let shortcutDescription: String
    let invocationPID: ProcessID?
    var candidates: [SwitchableWindow]
    let origin: WindowIdentity?
    var selectedIndex: Int
    var phase: SwitcherSessionPhase
    var panelIsVisible = false
    let panelPresentationDeadlineMilliseconds: Int64

    var target: SwitchableWindow { candidates[selectedIndex] }

    var panelState: SwitcherPanelState {
        SwitcherPanelState(
            mode: mode,
            shortcutDescription: shortcutDescription,
            rows: candidates.map { candidate in
                SwitcherPanelRow(
                    identity: candidate.identity,
                    title: candidate.title ?? "Untitled Window",
                    applicationName: candidate.applicationName
                        ?? candidate.bundleIdentifier
                        ?? "Application \(candidate.pid)",
                    applicationBundlePath: candidate.applicationBundlePath,
                    isMinimized: candidate.isMinimized,
                    applicationIsHidden: candidate.applicationIsHidden,
                    isFullscreen: candidate.isFullscreen
                )
            },
            selectedIdentity: target.identity
        )
    }
}

enum SwitchingEvent: Equatable, Sendable {
    case deminimizeCompleted(WindowIdentity, succeeded: Bool)
    case focusCompleted(WindowIdentity, succeeded: Bool)
    case focusPostconditionObserved(FocusedWindow?)
    case failedFocusRecoveryCompleted(WindowIdentity)
}

/// The application-service seam. It owns only value state and requested effects;
/// concrete AppKit and system adapter types remain outside it.
@MainActor
final class SwitcherEngine {
    private let inventory: any InventoryAdapter
    private let clock: any SwitcherClock
    private var suppressedFocusPromotions: Set<WindowIdentity> = []
    private(set) var activeSwitchSession: SwitcherSession?

    private(set) var presentationState = SwitcherPresentationState(
        hasLaunched: false,
        accessibility: .unknown,
        windowServer: .unknown
    )

    init(
        inventory: any InventoryAdapter = WindowInventory(),
        clock: any SwitcherClock = SystemSwitcherClock(),
        shortcuts: ShortcutPair = .defaults,
        settingsWarning: String? = nil
    ) {
        self.inventory = inventory
        self.clock = clock
        presentationState.shortcutSettings = ShortcutSettingsState(
            current: shortcuts,
            pending: nil,
            error: nil,
            recoveryWarning: settingsWarning
        )
    }

    func receiveInventory(_ event: InventoryEvent) async -> [SwitcherEffect] {
        if case let .focused(identity) = event {
            if suppressedFocusPromotions.contains(identity) { return [] }
            if let session = activeSwitchSession,
               identity == session.target.identity,
               session.phase != .waitingForModifierRelease {
                return []
            }
        }
        let identities = await inventory.apply(event)
        var effects: [SwitcherEffect] = identities.isEmpty ? [] : [.enrichWindows(identities)]
        if let session = activeSwitchSession,
           session.phase == .waitingForModifierRelease,
           eventLosesInteractionContext(event, session: session) {
            effects.append(contentsOf: endSessionEffects())
            return effects
        }
        guard eventCanInvalidateCapturedCandidates(event),
              let session = activeSwitchSession else { return effects }

        let snapshot = await inventory.snapshot()
        let liveIdentities = Set(snapshot.windows.map(\.identity))
        if snapshot.generation != session.target.generation {
            effects.append(contentsOf: endSessionEffects())
            return effects
        }

        let selectedIdentity = session.target.identity
        let selectedIndex = session.selectedIndex
        var updated = session
        updated.candidates.removeAll { !liveIdentities.contains($0.identity) }
        if session.phase == .waitingForModifierRelease {
            guard !updated.candidates.isEmpty else {
                effects.append(contentsOf: endSessionEffects())
                return effects
            }
            updated.selectedIndex = updated.candidates.firstIndex {
                $0.identity == selectedIdentity
            } ?? selectedIndex % updated.candidates.count
            activeSwitchSession = updated
            if updated.panelIsVisible, updated != session {
                effects.append(.updateSwitcherPanel(updated.panelState))
            }
            return effects
        }

        guard updated.candidates.contains(where: { $0.identity == selectedIdentity }) else {
            effects.append(contentsOf: failActiveSwitch(session))
            return effects
        }
        updated.selectedIndex = updated.candidates.firstIndex {
            $0.identity == selectedIdentity
        }!
        activeSwitchSession = updated
        return effects
    }

    func inventorySnapshot() async -> WindowInventorySnapshot {
        await inventory.snapshot()
    }

    func beginAllWindowsSwitch(direction: SwitchDirection = .forward) async -> [SwitcherEffect] {
        await beginSwitch(mode: .allWindows, direction: direction)
    }

    func beginSwitch(
        mode: SwitcherMode,
        direction: SwitchDirection
    ) async -> [SwitcherEffect] {
        guard activeSwitchSession == nil else { return [] }
        let snapshot = await inventory.snapshot()
        let invocationPID = snapshot.frontmostApplicationPID
            ?? snapshot.focusedWindow?.pid
        let candidates = switch mode {
        case .allWindows:
            snapshot.windows
        case .currentApp:
            snapshot.windows.filter { $0.pid == invocationPID }
        }
        guard !candidates.isEmpty else { return [] }

        let origin = snapshot.focusedWindow
        if candidates.count == 1, candidates[0].identity == origin { return [] }

        let selectedIndex: Int
        if let origin, let currentIndex = candidates.firstIndex(where: { $0.identity == origin }) {
            switch direction {
            case .forward:
                selectedIndex = (currentIndex + 1) % candidates.count
            case .backward:
                selectedIndex = (currentIndex - 1 + candidates.count) % candidates.count
            }
        } else {
            selectedIndex = direction == .forward ? 0 : candidates.count - 1
        }
        activeSwitchSession = SwitcherSession(
            mode: mode,
            shortcutDescription: presentationState.shortcutSettings.current
                .binding(for: mode).displayName,
            invocationPID: invocationPID,
            candidates: candidates,
            origin: origin,
            selectedIndex: selectedIndex,
            phase: .waitingForModifierRelease,
            panelPresentationDeadlineMilliseconds: clock.nowMilliseconds + 125
        )

        if candidates.count == 1 { return confirmSwitch() }
        return [.scheduleSwitcherPanel(delayMilliseconds: 125)]
    }

    func invokeAllWindowsSwitch(direction: SwitchDirection) async -> [SwitcherEffect] {
        await invokeSwitch(mode: .allWindows, direction: direction)
    }

    func invokeSwitch(
        mode: SwitcherMode,
        direction: SwitchDirection
    ) async -> [SwitcherEffect] {
        guard let session = activeSwitchSession else {
            return await beginSwitch(mode: mode, direction: direction)
        }
        guard session.mode == mode else {
            return receiveSession(.cancel(.shortcutInterrupted))
        }
        return receiveSession(.navigate(direction))
    }

    func receiveSession(_ event: SwitcherSessionEvent) -> [SwitcherEffect] {
        guard var session = activeSwitchSession,
              session.phase == .waitingForModifierRelease else { return [] }
        switch event {
        case .panelDelayElapsed:
            guard !session.panelIsVisible,
                  clock.nowMilliseconds >= session.panelPresentationDeadlineMilliseconds else {
                return []
            }
            session.panelIsVisible = true
            activeSwitchSession = session
            return [.showSwitcherPanel(session.panelState)]
        case let .navigate(direction):
            guard session.candidates.count > 1 else { return [] }
            let delta = direction == .forward ? 1 : -1
            session.selectedIndex = (
                session.selectedIndex + delta + session.candidates.count
            ) % session.candidates.count
            activeSwitchSession = session
            return session.panelIsVisible ? [.updateSwitcherPanel(session.panelState)] : []
        case let .select(identity):
            guard let index = session.candidates.firstIndex(where: { $0.identity == identity }),
                  index != session.selectedIndex else { return [] }
            session.selectedIndex = index
            activeSwitchSession = session
            return session.panelIsVisible ? [.updateSwitcherPanel(session.panelState)] : []
        case let .confirm(identity):
            if let identity {
                guard let index = session.candidates.firstIndex(where: {
                    $0.identity == identity
                }) else { return [] }
                session.selectedIndex = index
                activeSwitchSession = session
            }
            return confirmSwitch()
        case .cancel:
            return endSessionEffects()
        }
    }

    func confirmSwitch() -> [SwitcherEffect] {
        guard var session = activeSwitchSession,
              session.phase == .waitingForModifierRelease else { return [] }
        session.phase = session.target.isMinimized ? .deminimizing : .focusing
        activeSwitchSession = session
        return session.target.isMinimized
            ? [.deminimizeWindow(session.target.identity)]
            : [.focusWindow(session.target.identity)]
    }

    func receiveSwitching(_ event: SwitchingEvent) async -> [SwitcherEffect] {
        if case let .failedFocusRecoveryCompleted(identity) = event {
            suppressedFocusPromotions.remove(identity)
            return []
        }
        guard var session = activeSwitchSession else { return [] }
        switch event {
        case let .deminimizeCompleted(identity, succeeded):
            guard session.phase == .deminimizing,
                  identity == session.target.identity else { return [] }
            guard succeeded else { return failActiveSwitch(session) }
            session.phase = .focusing
            activeSwitchSession = session
            return [.focusWindow(identity)]
        case let .focusCompleted(identity, succeeded):
            guard session.phase == .focusing,
                  identity == session.target.identity else { return [] }
            guard succeeded else { return failActiveSwitch(session) }
            session.phase = .verifying
            activeSwitchSession = session
            return [.verifyFocus(identity)]
        case let .focusPostconditionObserved(observed):
            guard session.phase == .verifying else { return [] }
            guard observed == FocusedWindow(
                wid: session.target.wid,
                pid: session.target.pid
            ) else { return failActiveSwitch(session) }
            _ = await inventory.apply(.focused(session.target.identity))
            return endSessionEffects()
        case .failedFocusRecoveryCompleted:
            return []
        }
    }

    private func failActiveSwitch(_ session: SwitcherSession) -> [SwitcherEffect] {
        suppressedFocusPromotions.insert(session.target.identity)
        let origin = session.origin == session.target.identity ? nil : session.origin
        return endSessionEffects(additional: [
            .recoverFailedFocus(target: session.target.identity, origin: origin),
            .presentSwitchingError(.unableToSwitch),
        ])
    }

    private func eventCanInvalidateCapturedCandidates(_ event: InventoryEvent) -> Bool {
        switch event {
        case .replaceActiveSpace, .reconcileActiveSpace, .created, .destroyed, .clear:
            true
        case .workspaceChanged(.terminated):
            true
        case .focused, .semanticsInvalidated, .semanticsChanged,
             .workspaceChanged(.snapshot), .workspaceChanged(.launched),
             .workspaceChanged(.hidden), .workspaceChanged(.activated):
            false
        }
    }

    private func eventLosesInteractionContext(
        _ event: InventoryEvent,
        session: SwitcherSession
    ) -> Bool {
        switch event {
        case let .focused(identity):
            identity != session.origin
        case let .workspaceChanged(.activated(pid)):
            session.invocationPID != pid
        default:
            false
        }
    }

    func send(_ command: SwitcherCommand) -> [SwitcherEffect] {
        switch command {
        case .launch:
            let shortcutSettings = presentationState.shortcutSettings
            activeSwitchSession = nil
            presentationState = SwitcherPresentationState(
                hasLaunched: true,
                accessibility: .unknown,
                windowServer: .unknown,
                shortcutSettings: shortcutSettings
            )
            return [.setShortcutsEnabled(false), .checkAccessibility, .checkWindowServer]
        case .accessibilityStatusMayHaveChanged:
            return [.checkAccessibility]
        case .systemDidWake:
            return beginReadinessCheck()
        case .openSettings:
            return [.presentSettings]
        case .requestAccessibility:
            return [.requestAccessibility, .checkAccessibility]
        case .checkForUpdates:
            return [.openReleasesPage]
        case .quit:
            return [.terminate]
        case .recheckReadiness:
            return beginReadinessCheck()
        case let .updateShortcut(mode, binding):
            return updateShortcut(mode: mode, binding: binding)
        }
    }

    func receiveShortcutRegistration(_ event: ShortcutRegistrationEvent) -> [SwitcherEffect] {
        switch event {
        case let .applied(pair):
            presentationState.shortcutSettings.current = pair
            presentationState.shortcutSettings.pending = nil
            presentationState.shortcutSettings.error = nil
            presentationState.shortcutSettings.recoveryWarning = nil
            return [.persistSettings(SettingsSnapshot(shortcuts: pair))]
        case let .failed(pair, error):
            if presentationState.shortcutSettings.pending == pair {
                presentationState.shortcutSettings.pending = nil
            }
            presentationState.shortcutSettings.error = error
            return []
        }
    }

    func receiveShortcutPersistenceFailure() {
        presentationState.shortcutSettings.error = .couldNotSaveSettings
    }

    private func updateShortcut(
        mode: SwitcherMode,
        binding: ShortcutBinding
    ) -> [SwitcherEffect] {
        let current = presentationState.shortcutSettings.current
        let pair = switch mode {
        case .allWindows:
            ShortcutPair(allWindows: binding, currentApp: current.currentApp)
        case .currentApp:
            ShortcutPair(allWindows: current.allWindows, currentApp: binding)
        }
        if let error = pair.validationError {
            presentationState.shortcutSettings.pending = nil
            presentationState.shortcutSettings.error = error
            return []
        }
        presentationState.shortcutSettings.pending = pair
        presentationState.shortcutSettings.error = nil
        return activeSwitchSession == nil ? [.replaceShortcuts(pair)] : []
    }

    private func endSessionEffects(
        additional: [SwitcherEffect] = []
    ) -> [SwitcherEffect] {
        activeSwitchSession = nil
        var effects: [SwitcherEffect] = [.endActiveSession]
        effects.append(contentsOf: additional)
        if let pending = presentationState.shortcutSettings.pending {
            effects.append(.replaceShortcuts(pending))
        }
        return effects
    }

    private func beginReadinessCheck() -> [SwitcherEffect] {
        let shortcutSettings = presentationState.shortcutSettings
        presentationState = SwitcherPresentationState(
            hasLaunched: presentationState.hasLaunched,
            accessibility: .unknown,
            windowServer: .unknown,
            shortcutSettings: shortcutSettings
        )
        var effects: [SwitcherEffect] = [.setShortcutsEnabled(false)]
        effects.append(contentsOf: endSessionEffects())
        effects.append(contentsOf: [
            .stopInventoryObservation,
            .clearInventory,
            .checkAccessibility,
            .checkWindowServer,
        ])
        return effects
    }

    func receive(_ event: SwitcherEvent) -> [SwitcherEffect] {
        let previousState = presentationState
        switch event {
        case let .accessibilityChanged(value):
            presentationState = SwitcherPresentationState(
                hasLaunched: presentationState.hasLaunched,
                accessibility: value,
                windowServer: presentationState.windowServer,
                shortcutSettings: presentationState.shortcutSettings
            )
        case let .windowServerChanged(value):
            presentationState = SwitcherPresentationState(
                hasLaunched: presentationState.hasLaunched,
                accessibility: presentationState.accessibility,
                windowServer: value,
                shortcutSettings: presentationState.shortcutSettings
            )
        }
        guard previousState != presentationState else { return [] }

        var effects: [SwitcherEffect] = []
        let accessibilityWasRevoked = previousState.accessibility == .available
            && presentationState.accessibility == .unavailable

        if previousState.isReady && !presentationState.isReady || accessibilityWasRevoked {
            effects.append(.setShortcutsEnabled(false))
            effects.append(contentsOf: endSessionEffects())
            effects.append(.stopInventoryObservation)
            effects.append(.clearInventory)
            if accessibilityWasRevoked {
                effects.append(.releaseAccessibilityObservers)
            }
        } else if !previousState.isReady && presentationState.isReady {
            effects.append(.setShortcutsEnabled(true))
            effects.append(.startInventoryObservation)
            effects.append(.refreshInventory(.replace))
        }

        switch event {
        case .accessibilityChanged(.available):
            effects.append(.recordDiagnostic(.accessibilityAvailable))
        case .accessibilityChanged(.unavailable):
            effects.append(.recordDiagnostic(.accessibilityUnavailable))
        case .windowServerChanged(.available):
            effects.append(.recordDiagnostic(.skyLightAvailable))
        case .windowServerChanged(.unavailable):
            effects.append(.recordDiagnostic(.skyLightUnavailable))
        case .accessibilityChanged(.unknown), .windowServerChanged(.unknown):
            break
        }
        return effects
    }
}
