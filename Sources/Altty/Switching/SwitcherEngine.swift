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
    var exceptionSettings = ExceptionSettingsState(
        current: [],
        pending: nil,
        error: nil,
        recoveryWarning: nil
    )
    var generalSettings = GeneralSettingsState(
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
    case requestMouseScrollPermission
    case checkForUpdates
    case openExternalPage(ExternalPage)
    case openLoginItemsSettings
    case quit
    case recheckReadiness
    case updateShortcut(SwitcherMode, ShortcutBinding)
    case replaceExceptionRules([ExceptionRule])
    case replaceGeneralSettings(GeneralSettings)
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
    case requestMouseScrollPermission
    case checkForUpdates
    case openExternalPage(ExternalPage)
    case openLoginItemsSettings
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
    case rollbackShortcuts(ShortcutPair)
    case setLaunchAtLogin(Bool)
    case setMouseScrollReversalEnabled(Bool)
    case persistSettings(SettingsSnapshot)
}

enum LaunchAtLoginEvent: Equatable, Sendable {
    case applied(Bool)
    case failed(Bool)
    case requiresApproval
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
    let invokingWindowIdentity: WindowIdentity?
    let listPresentation: ListPresentationPreferences

    init(
        mode: SwitcherMode,
        shortcutDescription: String,
        rows: [SwitcherPanelRow],
        selectedIdentity: WindowIdentity,
        invokingWindowIdentity: WindowIdentity? = nil,
        listPresentation: ListPresentationPreferences = .defaults
    ) {
        self.mode = mode
        self.shortcutDescription = shortcutDescription
        self.rows = rows
        self.selectedIdentity = selectedIdentity
        self.invokingWindowIdentity = invokingWindowIdentity
        self.listPresentation = listPresentation
    }

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
    let transactionID: UInt64
    let mode: SwitcherMode
    let shortcutDescription: String
    let invocationPID: ProcessID?
    var candidates: [SwitchableWindow]
    let origin: WindowIdentity?
    var selectedIndex: Int
    var phase: SwitcherSessionPhase
    var panelIsVisible = false
    let panelPresentationDeadlineMilliseconds: Int64
    let listPresentation: ListPresentationPreferences

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
            selectedIdentity: target.identity,
            invokingWindowIdentity: origin,
            listPresentation: listPresentation
        )
    }
}

enum SwitchingEvent: Equatable, Sendable {
    case deminimizeCompleted(WindowIdentity, succeeded: Bool)
    case focusCompleted(WindowIdentity, succeeded: Bool)
    case focusPostconditionObserved(FocusedWindow?)
}

/// The application-service seam. It owns only value state and requested effects;
/// concrete AppKit and system adapter types remain outside it.
@MainActor
final class SwitcherEngine {
    private static let launchAtLoginApprovalMessage = "macOS requires approval for Altty in System Settings > General > Login Items. Approve Altty, then try again."
    private let inventory: any InventoryAdapter
    private let clock: any SwitcherClock
    private var exceptionPolicy: ExceptionPolicy
    private var exceptionShortcutsEnabled: Bool? = true
    private var exceptionForegroundContext = ExceptionForegroundContext.unknown
    private var suppressedFocusPromotions: [WindowIdentity: Int] = [:]
    private var nextFocusTransactionID: UInt64 = 1
    private var activeSpaceRevision: UInt64 = 0
    private var activeSpaceIsCurrent = true
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
        exceptionRules: [ExceptionRule] = [],
        generalSettings: GeneralSettings = .defaults,
        launchAtLoginRequiresApproval: Bool = false,
        settingsWarning: String? = nil
    ) {
        self.inventory = inventory
        self.clock = clock
        self.exceptionPolicy = ExceptionPolicy(rules: exceptionRules)
        presentationState.shortcutSettings = ShortcutSettingsState(
            current: shortcuts,
            pending: nil,
            error: nil,
            recoveryWarning: settingsWarning
        )
        presentationState.exceptionSettings = ExceptionSettingsState(
            current: exceptionRules,
            pending: nil,
            error: nil,
            recoveryWarning: settingsWarning
        )
        presentationState.generalSettings = GeneralSettingsState(
            current: generalSettings,
            pending: nil,
            error: launchAtLoginRequiresApproval
                ? Self.launchAtLoginApprovalMessage
                : nil,
            recoveryWarning: settingsWarning,
            launchAtLoginRequiresApproval: launchAtLoginRequiresApproval
        )
    }

    func receiveInventory(_ event: InventoryEvent) async -> [SwitcherEffect] {
        var effects = await receiveInventorySessionEffects(event)
        let snapshot = await inventory.snapshot()
        exceptionForegroundContext = snapshot.exceptionForegroundContext
        let shouldEnable = exceptionPolicy.shortcutsShouldBeEnabled(
            in: exceptionForegroundContext
        )
        guard shouldEnable != exceptionShortcutsEnabled else { return effects }
        exceptionShortcutsEnabled = shouldEnable
        if presentationState.isReady, let shouldEnable {
            effects.append(.setShortcutsEnabled(shouldEnable))
        }
        return effects
    }

    private func receiveInventorySessionEffects(
        _ event: InventoryEvent
    ) async -> [SwitcherEffect] {
        if case let .focused(identity) = event {
            if suppressedFocusPromotions[identity, default: 0] > 0 { return [] }
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
        let liveIdentities = snapshot.liveIdentities
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

    /// Synchronous boundary: an invocation already awaiting the actor must also fail closed.
    func invalidateActiveSpace() -> [SwitcherEffect] {
        activeSpaceRevision &+= 1
        activeSpaceIsCurrent = false
        return activeSwitchSession == nil ? [] : endSessionEffects()
    }

    func activeSpaceRefreshCompleted() { activeSpaceIsCurrent = true }

    func isCurrentFocusTransaction(_ transactionID: UInt64) -> Bool {
        activeSpaceIsCurrent && activeSwitchSession?.transactionID == transactionID
    }

    func inventorySnapshot() async -> WindowInventorySnapshot {
        await inventory.snapshot()
    }

    func updateFrontmostApplication(_ bundleIdentifier: String?) {
        exceptionForegroundContext = ExceptionForegroundContext(
            bundleIdentifier: bundleIdentifier,
            windowIsFullscreen: nil
        )
        exceptionShortcutsEnabled = exceptionPolicy.shortcutsShouldBeEnabled(
            in: exceptionForegroundContext
        )
    }

    func beginAllWindowsSwitch(direction: SwitchDirection = .forward) async -> [SwitcherEffect] {
        await beginSwitch(mode: .allWindows, direction: direction)
    }

    func beginSwitch(
        mode: SwitcherMode,
        direction: SwitchDirection
    ) async -> [SwitcherEffect] {
        guard activeSpaceIsCurrent, activeSwitchSession == nil else { return [] }
        let revision = activeSpaceRevision
        let snapshot = await inventory.snapshot()
        guard activeSpaceIsCurrent, revision == activeSpaceRevision,
              activeSwitchSession == nil else { return [] }
        let invocationPID = snapshot.frontmostApplicationPID
            ?? snapshot.focusedWindow?.pid
        let visibleWindows = snapshot.windows.filter { window in
            !exceptionPolicy.disposition(for: window.bundleIdentifier).hidesWindows
        }
        let candidates = switch mode {
        case .allWindows:
            visibleWindows
        case .currentApp:
            visibleWindows.filter { $0.pid == invocationPID }
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
            transactionID: nextFocusTransactionID,
            mode: mode,
            shortcutDescription: presentationState.shortcutSettings.current
                .binding(for: mode).displayName,
            invocationPID: invocationPID,
            candidates: candidates,
            origin: origin,
            selectedIndex: selectedIndex,
            phase: .waitingForModifierRelease,
            panelPresentationDeadlineMilliseconds: clock.nowMilliseconds + 125,
            listPresentation: presentationState.generalSettings.current.listPresentation
        )
        nextFocusTransactionID &+= 1

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

    private func receiveSwitching(_ event: SwitchingEvent) async -> [SwitcherEffect] {
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
        }
    }

    func receiveSwitching(
        _ event: SwitchingEvent,
        transactionID: UInt64
    ) async -> [SwitcherEffect] {
        guard activeSwitchSession?.transactionID == transactionID else { return [] }
        return await receiveSwitching(event)
    }

    func completeFailedFocusRecovery(_ identity: WindowIdentity) {
        let remaining = suppressedFocusPromotions[identity, default: 0] - 1
        suppressedFocusPromotions[identity] = remaining > 0 ? remaining : nil
    }

    private func failActiveSwitch(_ session: SwitcherSession) -> [SwitcherEffect] {
        suppressedFocusPromotions[session.target.identity, default: 0] += 1
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
            let exceptionSettings = presentationState.exceptionSettings
            let generalSettings = presentationState.generalSettings
            activeSwitchSession = nil
            presentationState = SwitcherPresentationState(
                hasLaunched: true,
                accessibility: .unknown,
                windowServer: .unknown,
                shortcutSettings: shortcutSettings,
                exceptionSettings: exceptionSettings,
                generalSettings: generalSettings
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
        case .requestMouseScrollPermission:
            return [.requestMouseScrollPermission]
        case .checkForUpdates:
            return [.checkForUpdates]
        case let .openExternalPage(page):
            return [.openExternalPage(page)]
        case .openLoginItemsSettings:
            return [.openLoginItemsSettings]
        case .quit:
            return [.terminate]
        case .recheckReadiness:
            return beginReadinessCheck()
        case let .updateShortcut(mode, binding):
            return updateShortcut(mode: mode, binding: binding)
        case let .replaceExceptionRules(rules):
            return replaceExceptionRules(rules)
        case let .replaceGeneralSettings(settings):
            return replaceGeneralSettings(settings)
        }
    }

    func receiveLaunchAtLogin(_ event: LaunchAtLoginEvent) -> [SwitcherEffect] {
        switch event {
        case let .applied(enabled):
            guard let pending = presentationState.generalSettings.pending,
                  pending.launchAtLogin == enabled else { return [] }
            presentationState.generalSettings.launchAtLoginRequiresApproval = false
            return [.persistSettings(settingsSnapshot(source: .current, general: pending))]
        case let .failed(enabled):
            guard presentationState.generalSettings.pending?.launchAtLogin == enabled else {
                return []
            }
            presentationState.generalSettings.pending = nil
            presentationState.generalSettings.error = "Launch at login could not be changed. The previous setting remains active."
            return []
        case .requiresApproval:
            presentationState.generalSettings.pending = nil
            presentationState.generalSettings.launchAtLoginRequiresApproval = true
            presentationState.generalSettings.error = Self.launchAtLoginApprovalMessage
            return []
        }
    }

    func receiveLaunchAtLoginStatus(_ status: LaunchAtLoginStatus) -> [SwitcherEffect] {
        if status == .requiresApproval {
            return receiveLaunchAtLogin(.requiresApproval)
        }
        let isEnabled = status == .enabled
        let displayed = presentationState.generalSettings.displayed
        presentationState.generalSettings.launchAtLoginRequiresApproval = false
        if presentationState.generalSettings.error == Self.launchAtLoginApprovalMessage {
            presentationState.generalSettings.error = nil
        }
        guard displayed.launchAtLogin != isEnabled else { return [] }
        let reconciled = GeneralSettings(
            launchAtLogin: isEnabled,
            listPresentation: displayed.listPresentation,
            reverseMouseWheel: displayed.reverseMouseWheel
        )
        presentationState.generalSettings.pending = reconciled
        return [.persistSettings(settingsSnapshot(source: .current, general: reconciled))]
    }

    func receiveShortcutRegistration(_ event: ShortcutRegistrationEvent) -> [SwitcherEffect] {
        switch event {
        case let .applied(pair):
            presentationState.shortcutSettings.pending = pair
            presentationState.shortcutSettings.error = nil
            presentationState.shortcutSettings.recoveryWarning = nil
            return [.persistSettings(settingsSnapshot(shortcuts: pair))]
        case let .failed(pair, error):
            if presentationState.shortcutSettings.pending == pair {
                presentationState.shortcutSettings.pending = nil
            }
            if presentationState.exceptionSettings.pending != nil {
                presentationState.exceptionSettings.pending = nil
                presentationState.exceptionSettings.error = "The complete Settings change was not applied."
            }
            presentationState.shortcutSettings.error = error
            return []
        case let .recoveredWithDefaults(error):
            presentationState.shortcutSettings.pending = .defaults
            presentationState.shortcutSettings.error = nil
            presentationState.shortcutSettings.recoveryWarning = "Saved shortcuts were unavailable, so Altty restored the defaults. \(error.message)"
            return [.persistSettings(settingsSnapshot(
                source: .current,
                shortcuts: .defaults
            ))]
        }
    }

    func receiveSettingsPersistence(_ event: SettingsPersistenceEvent) -> [SwitcherEffect] {
        switch event {
        case let .saved(snapshot):
            let savesShortcuts = presentationState.shortcutSettings.pending == snapshot.shortcuts
            let savesExceptions = presentationState.exceptionSettings.pending
                == snapshot.exceptionRules
            let savesGeneral = presentationState.generalSettings.pending == snapshot.general
            guard savesShortcuts || savesExceptions || savesGeneral else { return [] }
            if savesShortcuts {
                presentationState.shortcutSettings.current = snapshot.shortcuts
                presentationState.shortcutSettings.pending = nil
                presentationState.shortcutSettings.error = nil
            }
            var effects: [SwitcherEffect] = []
            if savesExceptions {
                presentationState.exceptionSettings.current = snapshot.exceptionRules
                presentationState.exceptionSettings.pending = nil
                presentationState.exceptionSettings.error = nil
                presentationState.exceptionSettings.recoveryWarning = nil
                exceptionPolicy = ExceptionPolicy(rules: snapshot.exceptionRules)
                effects.append(contentsOf: reconcileExceptionShortcutPolicy())
            }
            if savesGeneral {
                let mouseScrollChanged = presentationState.generalSettings.current.reverseMouseWheel
                    != snapshot.general.reverseMouseWheel
                presentationState.generalSettings.current = snapshot.general
                presentationState.generalSettings.pending = nil
                presentationState.generalSettings.error = nil
                presentationState.generalSettings.recoveryWarning = nil
                presentationState.generalSettings.launchAtLoginRequiresApproval = false
                if mouseScrollChanged {
                    effects.append(.setMouseScrollReversalEnabled(
                        snapshot.general.reverseMouseWheel && presentationState.accessibility == .available
                    ))
                }
            }
            return effects
        case let .failed(snapshot):
            var effects: [SwitcherEffect] = []
            if presentationState.shortcutSettings.pending == snapshot.shortcuts {
                presentationState.shortcutSettings.pending = nil
                presentationState.shortcutSettings.error = .couldNotSaveSettings
                effects.append(.rollbackShortcuts(
                    presentationState.shortcutSettings.current
                ))
            }
            if presentationState.exceptionSettings.pending == snapshot.exceptionRules {
                presentationState.exceptionSettings.pending = nil
                presentationState.exceptionSettings.error = "Exception changes could not be saved. Previous rules remain active."
            }
            if presentationState.generalSettings.pending == snapshot.general {
                let shouldRollbackLoginItem = snapshot.general.launchAtLogin
                    != presentationState.generalSettings.current.launchAtLogin
                presentationState.generalSettings.pending = nil
                presentationState.generalSettings.error = "General settings could not be saved. Previous settings remain active."
                if shouldRollbackLoginItem {
                    effects.append(.setLaunchAtLogin(
                        presentationState.generalSettings.current.launchAtLogin
                    ))
                }
            }
            return effects
        }
    }

    private func updateShortcut(
        mode: SwitcherMode,
        binding: ShortcutBinding
    ) -> [SwitcherEffect] {
        let current = presentationState.shortcutSettings.pending
            ?? presentationState.shortcutSettings.current
        let pair = current.replacing(mode, with: binding)
        if let error = pair.validationError {
            presentationState.shortcutSettings.pending = nil
            presentationState.shortcutSettings.error = error
            return []
        }
        presentationState.shortcutSettings.pending = pair
        presentationState.shortcutSettings.error = nil
        return activeSwitchSession == nil ? [.replaceShortcuts(pair)] : []
    }

    private func replaceExceptionRules(_ rules: [ExceptionRule]) -> [SwitcherEffect] {
        var normalized: [ExceptionRule] = []
        for rule in rules {
            normalized = ExceptionRule.replacingDuplicateIdentity(
                in: normalized,
                with: rule
            )
        }
        if normalized == presentationState.exceptionSettings.current {
            presentationState.exceptionSettings.pending = nil
            presentationState.exceptionSettings.error = nil
            return []
        }
        presentationState.exceptionSettings.pending = normalized
        presentationState.exceptionSettings.error = nil
        guard activeSwitchSession == nil else { return [] }
        return [.persistSettings(settingsSnapshot(exceptionRules: normalized))]
    }

    private func replaceGeneralSettings(_ settings: GeneralSettings) -> [SwitcherEffect] {
        guard settings.isValid else {
            presentationState.generalSettings.pending = nil
            presentationState.generalSettings.error = "List presentation must show between six and eight rows."
            return []
        }
        guard settings != presentationState.generalSettings.current else {
            presentationState.generalSettings.pending = nil
            presentationState.generalSettings.error = nil
            return []
        }
        presentationState.generalSettings.pending = settings
        presentationState.generalSettings.error = nil
        if settings.launchAtLogin != presentationState.generalSettings.current.launchAtLogin {
            return [.setLaunchAtLogin(settings.launchAtLogin)]
        }
        return [.persistSettings(settingsSnapshot(source: .current, general: settings))]
    }

    private enum SettingsSnapshotSource {
        case current
        case displayed
    }

    private func settingsSnapshot(
        source: SettingsSnapshotSource = .displayed,
        shortcuts: ShortcutPair? = nil,
        exceptionRules: [ExceptionRule]? = nil,
        general: GeneralSettings? = nil
    ) -> SettingsSnapshot {
        let usesPending = source == .displayed
        return SettingsSnapshot(
            shortcuts: shortcuts
                ?? (usesPending ? presentationState.shortcutSettings.pending : nil)
                ?? presentationState.shortcutSettings.current,
            exceptionRules: exceptionRules
                ?? (usesPending ? presentationState.exceptionSettings.pending : nil)
                ?? presentationState.exceptionSettings.current,
            general: general
                ?? (usesPending ? presentationState.generalSettings.pending : nil)
                ?? presentationState.generalSettings.current
        )
    }

    private func endSessionEffects(
        additional: [SwitcherEffect] = []
    ) -> [SwitcherEffect] {
        activeSwitchSession = nil
        var effects: [SwitcherEffect] = [.endActiveSession]
        effects.append(contentsOf: additional)
        if let pending = presentationState.shortcutSettings.pending {
            effects.append(.replaceShortcuts(pending))
        } else if let pending = presentationState.exceptionSettings.pending {
            effects.append(.persistSettings(settingsSnapshot(exceptionRules: pending)))
        }
        return effects
    }

    private func reconcileExceptionShortcutPolicy() -> [SwitcherEffect] {
        let shouldEnable = exceptionPolicy.shortcutsShouldBeEnabled(
            in: exceptionForegroundContext
        )
        guard shouldEnable != exceptionShortcutsEnabled else { return [] }
        exceptionShortcutsEnabled = shouldEnable
        guard presentationState.isReady, let shouldEnable else { return [] }
        return [.setShortcutsEnabled(shouldEnable)]
    }

    private func beginReadinessCheck() -> [SwitcherEffect] {
        let shortcutSettings = presentationState.shortcutSettings
        let exceptionSettings = presentationState.exceptionSettings
        let generalSettings = presentationState.generalSettings
        presentationState = SwitcherPresentationState(
            hasLaunched: presentationState.hasLaunched,
            accessibility: .unknown,
            windowServer: .unknown,
            shortcutSettings: shortcutSettings,
            exceptionSettings: exceptionSettings,
            generalSettings: generalSettings
        )
        var effects: [SwitcherEffect] = [.setShortcutsEnabled(false)]
        if generalSettings.current.reverseMouseWheel {
            effects.append(.setMouseScrollReversalEnabled(false))
        }
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
                shortcutSettings: presentationState.shortcutSettings,
                exceptionSettings: presentationState.exceptionSettings,
                generalSettings: presentationState.generalSettings
            )
        case let .windowServerChanged(value):
            presentationState = SwitcherPresentationState(
                hasLaunched: presentationState.hasLaunched,
                accessibility: presentationState.accessibility,
                windowServer: value,
                shortcutSettings: presentationState.shortcutSettings,
                exceptionSettings: presentationState.exceptionSettings,
                generalSettings: presentationState.generalSettings
            )
        }
        guard previousState != presentationState else { return [] }

        var effects: [SwitcherEffect] = []
        if previousState.accessibility != presentationState.accessibility,
           presentationState.generalSettings.current.reverseMouseWheel {
            effects.append(.setMouseScrollReversalEnabled(presentationState.accessibility == .available))
        }
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
            if let exceptionShortcutsEnabled {
                effects.append(.setShortcutsEnabled(exceptionShortcutsEnabled))
            }
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

    func receiveMouseScrollStatus(_ status: MouseScrollStatus) {
        presentationState.generalSettings.mouseScrollStatus = status
    }
}
