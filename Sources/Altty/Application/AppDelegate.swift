import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment
    private var isMonitoringInventory = false
    private var inventoryRefreshCoalescer = InventoryRefreshCoalescer()
    private var inventoryRefreshTask: Task<Void, Never>?
    private var inventoryRefreshSequence: UInt64 = 0
    private var inventoryGeneration: InventoryGeneration = 0
    private var semanticInvalidationTasks: [WindowIdentity: Task<Void, Never>] = [:]
    private var shortcutInvocationTask: Task<Void, Never>?
    private var shortcutCleanupTask: Task<Void, Never>?
    private var switcherPanelTask: Task<Void, Never>?
    private var shortcutPerformance = ShortcutPerformanceTracker()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.presentation.install { [weak self] command in self?.handle(command) }
        environment.presentation.installSwitcherInteractions { [weak self] event in
            guard let self else { return }
            self.run(self.environment.engine.receiveSession(event))
        }
        environment.input.install { [weak self] event in self?.receive(event) }
        environment.accessibility.startMonitoringAvailability { [weak self] availability in
            self?.receive(.accessibilityChanged(availability))
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        handle(.launch)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        shortcutInvocationTask?.cancel()
        shortcutCleanupTask?.cancel()
        switcherPanelTask?.cancel()
        environment.presentation.dismissSwitcherPanel()
        environment.input.setShortcutsEnabled(false)
        stopInventoryObservation()
        environment.accessibility.stopMonitoringAvailability()
        environment.accessibility.releaseObservers()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard environment.engine.presentationState.hasLaunched else { return }
        run(environment.engine.receiveLaunchAtLoginStatus(
            environment.launchAtLogin.status
        ))
        refreshPresentation()
    }

    private func handle(_ command: SwitcherCommand) {
        run(environment.engine.send(command))
        refreshPresentation()
    }

    private func receive(_ event: SwitcherEvent) {
        environment.engine.updateFrontmostApplication(
            environment.exceptions.frontmostApplicationBundleIdentifier()
        )
        run(environment.engine.receive(event))
        refreshPresentation()
    }

    private func receive(_ event: ShortcutEvent) {
        switch event {
        case let .switcherPressed(mode, direction):
            if environment.engine.activeSwitchSession == nil { shortcutPerformance.beginIfNeeded() }
            let priorInvocation = shortcutInvocationTask
            shortcutInvocationTask = Task { [weak self] in
                await priorInvocation?.value
                guard let self else { return }
                self.run(await self.environment.engine.invokeSwitch(
                    mode: mode,
                    direction: direction
                ))
                self.refreshPresentation()
            }
        case .holdModifiersReleased:
            let invocation = shortcutInvocationTask
            shortcutInvocationTask = nil
            Task { [weak self] in
                await invocation?.value
                guard let self else { return }
                self.run(self.environment.engine.confirmSwitch())
                self.refreshPresentation()
            }
        case let .cancel(reason):
            shortcutPerformance.cancel()
            let invocation = shortcutInvocationTask
            shortcutInvocationTask = nil
            Task { [weak self] in
                await invocation?.value
                guard let self else { return }
                self.run(self.environment.engine.receiveSession(.cancel(reason)))
            }
        }
    }

    private func receive(_ event: SwitchingEvent, transactionID: UInt64) {
        Task { [weak self] in
            guard let self else { return }
            self.run(await self.environment.engine.receiveSwitching(
                event,
                transactionID: transactionID
            ))
            self.refreshPresentation()
        }
    }

    private func run(_ effects: [SwitcherEffect]) {
        for effect in effects {
            switch effect {
            case .checkAccessibility:
                recordAdapterCall(.accessibility)
                receive(.accessibilityChanged(environment.accessibility.availability()))
            case .checkWindowServer:
                recordAdapterCall(.skyLight)
                receive(.windowServerChanged(environment.windowServer.availability()))
            case let .setShortcutsEnabled(enabled):
                setShortcutsEnabled(enabled)
            case .endActiveSession:
                switcherPanelTask?.cancel()
                switcherPanelTask = nil
                environment.presentation.dismissSwitcherPanel()
                environment.switching.endActiveSession()
            case .releaseAccessibilityObservers:
                environment.accessibility.releaseObservers()
            case let .recordDiagnostic(event):
                environment.diagnostics.record(event)
            case .presentSettings:
                environment.presentation.presentSettings(state: environment.engine.presentationState)
            case .requestAccessibility:
                environment.accessibility.requestPermission()
            case .checkForUpdates:
                environment.presentation.checkForUpdates()
            case let .openExternalPage(page):
                environment.presentation.openExternalPage(page)
            case .openLoginItemsSettings:
                environment.launchAtLogin.openSystemSettings()
            case .terminate:
                NSApp.terminate(nil)
            case let .enrichWindows(identities):
                enrich(identities)
            case .startInventoryObservation:
                startInventoryObservation()
            case .stopInventoryObservation:
                stopInventoryObservation()
            case let .refreshInventory(mode):
                scheduleInventoryRefresh(mode)
            case .clearInventory:
                Task { [weak self] in
                    guard let self else { return }
                    self.run(await self.environment.engine.receiveInventory(.clear))
                    self.inventoryGeneration = await self.environment.engine.inventorySnapshot().generation
                }
            case let .deminimizeWindow(identity):
                recordShortcutLatency(.shortcutToFocusStart)
                dismissSwitcherPanelForConfirmation()
                let transactionID = environment.engine.activeSwitchSession?.transactionID
                Task { [weak self] in
                    guard let self else { return }
                    self.recordAdapterCall(.accessibility)
                    let succeeded = await self.environment.accessibility.deminimize(identity)
                    guard let transactionID else { return }
                    self.receive(
                        .deminimizeCompleted(identity, succeeded: succeeded),
                        transactionID: transactionID
                    )
                }
            case let .focusWindow(identity):
                recordShortcutLatency(.shortcutToFocusStart)
                dismissSwitcherPanelForConfirmation()
                guard let transactionID = environment.engine.activeSwitchSession?.transactionID else {
                    break
                }
                focusTarget(identity, transactionID: transactionID)
            case let .verifyFocus(identity):
                guard let transactionID = environment.engine.activeSwitchSession?.transactionID else {
                    break
                }
                verifyFocus(identity, transactionID: transactionID)
            case let .recoverFailedFocus(target, origin):
                recoverFailedFocus(target: target, origin: origin)
            case let .presentSwitchingError(error):
                environment.presentation.presentSwitchingError(error)
            case let .scheduleSwitcherPanel(delayMilliseconds):
                scheduleSwitcherPanel(delayMilliseconds: delayMilliseconds)
            case let .showSwitcherPanel(state):
                recordShortcutLatency(.shortcutToPanelPresentation, clearStart: false)
                environment.presentation.showSwitcherPanel(state: state)
            case let .updateSwitcherPanel(state):
                environment.presentation.updateSwitcherPanel(state: state)
            case let .replaceShortcuts(pair):
                let result = environment.input.replaceShortcuts(pair)
                switch result {
                case .applied:
                    run(environment.engine.receiveShortcutRegistration(.applied(pair)))
                case .staged:
                    break
                case let .failure(error):
                    run(environment.engine.receiveShortcutRegistration(.failed(pair, error)))
                    if error == .inputMonitoringUnavailable {
                        scheduleShortcutCleanupRetry()
                    }
                }
                refreshPresentation()
            case let .rollbackShortcuts(pair):
                if case let .failure(error) = environment.input.replaceShortcuts(pair) {
                    run(environment.engine.receiveShortcutRegistration(.failed(pair, error)))
                    scheduleShortcutCleanupRetry()
                }
                refreshPresentation()
            case let .setLaunchAtLogin(enabled):
                do {
                    let status = try environment.launchAtLogin.setEnabled(enabled)
                    if enabled, status == .requiresApproval {
                        run(environment.engine.receiveLaunchAtLogin(.requiresApproval))
                    } else if status == (enabled ? .enabled : .disabled) {
                        run(environment.engine.receiveLaunchAtLogin(.applied(enabled)))
                    } else {
                        run(environment.engine.receiveLaunchAtLogin(.failed(enabled)))
                    }
                } catch {
                    run(environment.engine.receiveLaunchAtLogin(.failed(enabled)))
                }
                refreshPresentation()
            case let .persistSettings(snapshot):
                do {
                    try environment.persistence.saveSettings(snapshot)
                    run(environment.engine.receiveSettingsPersistence(.saved(snapshot)))
                } catch {
                    run(environment.engine.receiveSettingsPersistence(.failed(snapshot)))
                }
                refreshPresentation()
            }
        }
    }

    private func setShortcutsEnabled(_ enabled: Bool) {
        let result = environment.input.setShortcutsEnabled(enabled)
        guard enabled else {
            if case let .failure(error) = result {
                run(environment.engine.receiveShortcutRegistration(.failed(
                    environment.input.configuredShortcuts,
                    error
                )))
                scheduleShortcutCleanupRetry()
            }
            return
        }

        switch result {
        case .applied:
            if environment.engine.presentationState.shortcutSettings.pending
                == environment.input.configuredShortcuts {
                run(environment.engine.receiveShortcutRegistration(.applied(
                    environment.input.configuredShortcuts
                )))
            }
        case .staged:
            break
        case let .failure(error):
            recoverFromUnavailableShortcuts(error)
        }
    }

    private func recoverFromUnavailableShortcuts(_ error: ShortcutConfigurationError) {
        let unavailable = environment.input.configuredShortcuts
        let settings = environment.engine.presentationState.shortcutSettings
        if settings.pending == unavailable {
            run(environment.engine.receiveShortcutRegistration(.failed(unavailable, error)))
            _ = environment.input.replaceShortcuts(settings.current)
            if case let .failure(restoreError) = environment.input.setShortcutsEnabled(true) {
                run(environment.engine.receiveShortcutRegistration(.failed(
                    settings.current,
                    restoreError
                )))
            }
            return
        }

        guard unavailable != .defaults else {
            run(environment.engine.receiveShortcutRegistration(.failed(unavailable, error)))
            return
        }
        _ = environment.input.replaceShortcuts(.defaults)
        switch environment.input.setShortcutsEnabled(true) {
        case .applied:
            run(environment.engine.receiveShortcutRegistration(
                .recoveredWithDefaults(error)
            ))
        case .staged:
            break
        case let .failure(defaultError):
            run(environment.engine.receiveShortcutRegistration(.failed(
                unavailable,
                defaultError
            )))
        }
    }

    private func scheduleShortcutCleanupRetry() {
        shortcutCleanupTask?.cancel()
        shortcutCleanupTask = Task { [weak self] in
            for delay in [50, 150, 300] {
                do {
                    try await Task.sleep(for: .milliseconds(delay))
                } catch {
                    return
                }
                guard let self else { return }
                if self.environment.input.setShortcutsEnabled(false) == .applied {
                    self.shortcutCleanupTask = nil
                    return
                }
            }
            self?.shortcutCleanupTask = nil
        }
    }

    private func scheduleSwitcherPanel(delayMilliseconds: Int) {
        switcherPanelTask?.cancel()
        switcherPanelTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            } catch {
                return
            }
            guard let self else { return }
            self.switcherPanelTask = nil
            self.run(self.environment.engine.receiveSession(.panelDelayElapsed))
        }
    }

    private func dismissSwitcherPanelForConfirmation() {
        switcherPanelTask?.cancel()
        switcherPanelTask = nil
        environment.presentation.dismissSwitcherPanel()
    }

    private func focusTarget(_ identity: WindowIdentity, transactionID: UInt64) {
        Task { [weak self] in
            guard let self else { return }
            self.recordAdapterCall(.skyLight)
            let succeeded = await self.environment.windowServer.focus(identity)
            self.receive(
                .focusCompleted(identity, succeeded: succeeded),
                transactionID: transactionID
            )
        }
    }

    private func recoverFailedFocus(target: WindowIdentity, origin: WindowIdentity?) {
        Task { [weak self] in
            guard let self else { return }
            if let origin {
                self.recordAdapterCall(.skyLight)
                _ = await self.environment.windowServer.focus(origin)
            }
            try? await Task.sleep(for: .milliseconds(100))
            self.environment.engine.completeFailedFocusRecovery(target)
        }
    }

    private func verifyFocus(_ identity: WindowIdentity, transactionID: UInt64) {
        Task { [weak self] in
            guard let self else { return }
            var observed: FocusedWindow?
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(25))
                self.recordAdapterCall(.accessibility)
                observed = await self.environment.accessibility.focusedWindow()
                if observed == FocusedWindow(wid: identity.wid, pid: identity.pid) { break }
            }
            self.receive(
                .focusPostconditionObserved(observed),
                transactionID: transactionID
            )
        }
    }

    private func startInventoryObservation() {
        guard !isMonitoringInventory else { return }
        isMonitoringInventory = true
        environment.windowServer.startMonitoringInventory { [weak self] event in
            self?.receive(event)
        }
        environment.accessibility.startMonitoringInventory { [weak self] event in
            self?.receive(event)
        }
        environment.workspace.startMonitoring { [weak self] event in
            self?.receive(event)
        }

        let facts = environment.workspace.runningApplications()
        Task { [weak self] in
            guard let self else { return }
            self.run(await self.environment.engine.receiveInventory(
                .workspaceChanged(.snapshot(facts))
            ))
        }
    }

    private func stopInventoryObservation() {
        guard isMonitoringInventory else { return }
        isMonitoringInventory = false
        inventoryRefreshTask?.cancel()
        inventoryRefreshTask = nil
        inventoryRefreshSequence &+= 1
        inventoryRefreshCoalescer.reset()
        semanticInvalidationTasks.values.forEach { $0.cancel() }
        semanticInvalidationTasks.removeAll()
        environment.windowServer.stopMonitoringInventory()
        environment.accessibility.stopMonitoringInventory()
        environment.workspace.stopMonitoring()
    }

    private func receive(_ event: WindowServerInventoryEvent) {
        switch event {
        case .created:
            scheduleInventoryRefresh(.reconcile)
        case let .destroyed(identity):
            Task { [weak self] in
                guard let self else { return }
                self.run(await self.environment.engine.receiveInventory(.destroyed(identity)))
            }
            scheduleInventoryRefresh(.reconcile)
        case let .focused(identity):
            Task { [weak self] in
                guard let self else { return }
                self.run(await self.environment.engine.receiveInventory(.focused(identity)))
            }
        case .focusNeedsReconciliation:
            scheduleInventoryRefresh(.reconcile)
        case let .semanticsInvalidated(identity):
            scheduleSemanticInvalidation(identity)
        case .activeSpaceChanged:
            scheduleInventoryRefresh(.replace)
        }
    }

    private func receive(_ event: AccessibilityInventoryEvent) {
        switch event {
        case .created, .destroyed:
            scheduleInventoryRefresh(.reconcile)
        case let .focused(pid, wid):
            if let wid {
                scheduleSemanticInvalidation(WindowIdentity(
                    wid: wid,
                    pid: pid,
                    generation: inventoryGeneration
                ))
            }
        case let .semanticsChanged(pid, wid):
            if let wid {
                scheduleSemanticInvalidation(WindowIdentity(
                    wid: wid,
                    pid: pid,
                    generation: inventoryGeneration
                ))
            }
        }
    }

    private func receive(_ event: WorkspaceApplicationEvent) {
        if case let .launched(facts) = event {
            environment.accessibility.observeApplication(pid: facts.pid)
        }
        if case let .terminated(pid) = event {
            environment.accessibility.stopObservingApplication(pid: pid)
        }
        Task { [weak self] in
            guard let self else { return }
            self.run(await self.environment.engine.receiveInventory(.workspaceChanged(event)))
        }
        switch event {
        case .launched, .terminated:
            scheduleInventoryRefresh(.reconcile)
        case .snapshot, .hidden, .activated:
            break
        }
    }

    private func scheduleSemanticInvalidation(_ identity: WindowIdentity) {
        semanticInvalidationTasks[identity]?.cancel()
        semanticInvalidationTasks[identity] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(75))
            } catch {
                return
            }
            guard let self, self.isMonitoringInventory else { return }
            self.semanticInvalidationTasks[identity] = nil
            self.run(await self.environment.engine.receiveInventory(.semanticsInvalidated(identity)))
        }
    }

    private func enrich(_ identities: [WindowIdentity]) {
        for identity in identities {
            Task { [weak self] in
                guard let self else { return }
                let patch = await self.environment.accessibility.enrichment(for: identity)
                self.run(await self.environment.engine.receiveInventory(
                    .semanticsChanged(identity, patch)
                ))
            }
        }
    }

    private func scheduleInventoryRefresh(_ mode: InventoryRefreshMode) {
        guard isMonitoringInventory else { return }
        inventoryRefreshCoalescer.request(mode)
        inventoryRefreshSequence &+= 1
        let sequence = inventoryRefreshSequence
        inventoryRefreshTask?.cancel()
        inventoryRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(75))
            } catch {
                return
            }
            guard let self, self.isMonitoringInventory,
                  let mode = self.inventoryRefreshCoalescer.takePending() else { return }
            self.recordAdapterCall(.skyLight)
            let snapshot = await self.environment.windowServer.activeSpaceSnapshot()
            guard !Task.isCancelled, self.isMonitoringInventory,
                  sequence == self.inventoryRefreshSequence else { return }
            guard let snapshot else {
                self.receive(.windowServerChanged(.unavailable))
                return
            }
            let event: InventoryEvent = mode == .replace
                ? .replaceActiveSpace(snapshot)
                : .reconcileActiveSpace(snapshot)
            self.run(await self.environment.engine.receiveInventory(event))
            self.inventoryGeneration = await self.environment.engine.inventorySnapshot().generation
            guard self.environment.windowServer.acceptInventorySnapshot(
                snapshot,
                generation: self.inventoryGeneration
            ) else {
                self.receive(.windowServerChanged(.unavailable))
                return
            }
        }
    }

    private func refreshPresentation() {
        let state = environment.engine.presentationState
        environment.presentation.update(state: state)
    }

    private func recordAdapterCall(_ adapter: PerformanceAdapter) {
        environment.diagnostics.recordPerformance(.adapterCall(adapter))
    }

    private func recordShortcutLatency(
        _ metric: PerformanceMetric,
        clearStart: Bool = true
    ) {
        guard let nanoseconds = shortcutPerformance.latency(clearStart: clearStart) else { return }
        environment.diagnostics.recordPerformance(.latency(metric, nanoseconds: nanoseconds))
    }

    @objc private func systemDidWake() { handle(.systemDidWake) }
}
