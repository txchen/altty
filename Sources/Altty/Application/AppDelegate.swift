import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment
    private var isMonitoringInventory = false
    private lazy var inventoryRefresh = InventoryRefreshScheduler(
        query: { [weak self] in
            guard let self else { return nil }
            self.recordAdapterCall(.skyLight)
            return await self.environment.windowServer.activeSpaceSnapshot()
        },
        apply: { [weak self] snapshot, mode, revision in
            await self?.applyInventoryRefresh(snapshot, mode: mode, revision: revision)
        }
    )
    private var inventoryObservationRevision: UInt64 = 0
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
        environment.hintShortcut.install { [weak self] in self?.environment.hints.toggleSession() }
        environment.mouseScroll.installStatusHandler { [weak self] status in
            guard let self else { return }
            self.environment.engine.receiveMouseScrollStatus(status)
            self.refreshPresentation()
        }
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
        _ = environment.hintShortcut.setShortcut(nil)
        environment.hints.setShortcut(nil)
        environment.mouseScroll.setEnabled(false)
        stopInventoryObservation()
        environment.accessibility.stopMonitoringAvailability()
        environment.accessibility.releaseObservers()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard environment.engine.presentationState.hasLaunched else { return }
        run(environment.engine.receiveLaunchAtLoginStatus(
            environment.launchAtLogin.status
        ))
        if environment.engine.presentationState.generalSettings.current.reverseMouseWheel {
            run(environment.engine.send(.recheckReadiness))
        }
        refreshPresentation()
    }

    private func handle(_ command: SwitcherCommand) {
        run(environment.engine.send(command))
        refreshPresentation()
    }

    private func receive(_ event: SwitcherEvent) {
        run(environment.engine.updateFrontmostApplication(
            environment.exceptions.frontmostApplicationBundleIdentifier()
        ))
        run(environment.engine.receive(event))
        refreshPresentation()
    }

    private func receive(_ event: ShortcutEvent) {
        ShortcutDiagnostics.record("queued event=\(event)")
        let revision = inventoryRefresh.revision
        let previous = shortcutInvocationTask
        shortcutInvocationTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.inventoryRefresh.isCurrent(revision) else { return }
            ShortcutDiagnostics.record("handling event=\(event)")
            switch event {
            case let .switcherPressed(mode, direction):
                await self.environment.engine.waitForCommittedSwitch()
                guard !Task.isCancelled, self.inventoryRefresh.isCurrent(revision) else { return }
                if self.environment.engine.activeSwitchSession == nil { self.shortcutPerformance.beginIfNeeded() }
                let effects = await self.environment.engine.invokeSwitch(mode: mode, direction: direction)
                ShortcutDiagnostics.record("invoked effects=\(effects.count) transaction=\(self.environment.engine.activeSwitchSession?.transactionID ?? 0)")
                guard self.inventoryRefresh.isCurrent(revision) else { return }
                self.run(effects)
            case let .navigate(direction):
                self.run(self.environment.engine.receiveSession(.navigate(direction)))
            case .holdModifiersReleased:
                self.run(self.environment.engine.confirmSwitch())
            case let .cancel(reason):
                self.shortcutPerformance.cancel()
                self.run(self.environment.engine.receiveSession(.cancel(reason)))
            case .monitoringFailed:
                self.run(self.environment.engine.receiveShortcutRegistration(.failed(
                    self.environment.input.configuredShortcuts, .inputMonitoringUnavailable
                )))
            }
            self.refreshPresentation()
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
            case let .setHintShortcut(binding):
                let registered = environment.hintShortcut.setShortcut(binding)
                environment.hints.setShortcut(registered ? binding : nil)
                environment.engine.receiveHintShortcutStatus(registered: registered || binding == nil)
                refreshPresentation()
            case let .setMouseScrollReversalEnabled(enabled):
                environment.engine.receiveMouseScrollStatus(environment.mouseScroll.setEnabled(enabled))
                refreshPresentation()
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
            case .requestMouseScrollPermission:
                environment.mouseScroll.requestInputMonitoringPermission()
                handle(.recheckReadiness)
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
                    guard let self, let transactionID,
                          self.environment.engine.isCurrentFocusTransaction(transactionID) else { return }
                    self.recordAdapterCall(.accessibility)
                    let succeeded = await self.environment.accessibility.deminimize(identity)
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
                let preparationStarted = DispatchTime.now().uptimeNanoseconds
                environment.presentation.showSwitcherPanel(state: state)
                environment.diagnostics.recordPerformance(.latency(.panelPreparation,
                    nanoseconds: DispatchTime.now().uptimeNanoseconds - preparationStarted))
                recordShortcutLatency(.shortcutToPanelPresentation, clearStart: false)
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
                    DiagnosticLogging.shared.setEnabled(snapshot.general.diagnosticLoggingEnabled)
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
            guard let self,
                  self.environment.engine.isCurrentFocusTransaction(transactionID) else { return }
            self.recordAdapterCall(.skyLight)
            let executor = WindowFocusExecutor(windowServer: self.environment.windowServer,
                                               accessibility: self.environment.accessibility)
            let succeeded = await executor.focus(identity) {
                self.environment.engine.isCurrentFocusTransaction(transactionID)
            }
            self.receive(
                .focusCompleted(identity, succeeded: succeeded),
                transactionID: transactionID
            )
        }
    }

    private func recoverFailedFocus(target: WindowIdentity, origin: WindowIdentity?) {
        let revision = inventoryRefresh.revision
        Task { [weak self] in
            guard let self else { return }
            if let origin, self.inventoryRefresh.isCurrent(revision), self.isMonitoringInventory,
               self.environment.engine.activeSwitchSession == nil {
                self.recordAdapterCall(.skyLight)
                let executor = WindowFocusExecutor(windowServer: self.environment.windowServer,
                                                   accessibility: self.environment.accessibility)
                _ = await executor.focus(origin) {
                    self.inventoryRefresh.isCurrent(revision)
                        && self.environment.engine.activeSwitchSession == nil
                }
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
                guard self.environment.engine.isCurrentFocusTransaction(transactionID) else { return }
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
        let revision = inventoryObservationRevision
        environment.windowServer.startMonitoringInventory { [weak self] event in
            guard let self, self.isMonitoringInventory, self.inventoryObservationRevision == revision else { return }
            self.receive(event)
        }
        environment.accessibility.startMonitoringInventory { [weak self] event in
            guard let self, self.isMonitoringInventory, self.inventoryObservationRevision == revision else { return }
            self.receive(event)
        }
        environment.workspace.startMonitoring { [weak self] event in
            guard let self, self.isMonitoringInventory, self.inventoryObservationRevision == revision else { return }
            self.receive(event)
        }

        let facts = environment.workspace.runningApplications()
        Task { [weak self] in
            guard let self, self.isMonitoringInventory, self.inventoryObservationRevision == revision else { return }
            self.run(await self.environment.engine.receiveInventory(
                .workspaceChanged(.snapshot(facts))
            ))
        }
    }

    private func stopInventoryObservation() {
        guard isMonitoringInventory else { return }
        isMonitoringInventory = false
        inventoryObservationRevision &+= 1
        inventoryRefresh.reset()
        run(environment.engine.invalidateActiveSpace())
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
        let revision = inventoryObservationRevision
        if case let .launched(facts) = event {
            environment.accessibility.observeApplication(pid: facts.pid)
        }
        if case let .terminated(pid) = event {
            environment.accessibility.stopObservingApplication(pid: pid)
        }
        Task { [weak self] in
            guard let self else { return }
            guard self.isMonitoringInventory, self.inventoryObservationRevision == revision else { return }
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
        guard isMonitoringInventory, semanticInvalidationTasks[identity] == nil else { return }
        let revision = inventoryRefresh.revision
        semanticInvalidationTasks[identity] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(75))
            } catch {
                return
            }
            guard let self, self.isMonitoringInventory,
                  self.inventoryRefresh.isCurrent(revision) else { return }
            self.semanticInvalidationTasks[identity] = nil
            self.run(await self.environment.engine.receiveInventory(.semanticsInvalidated(identity)))
        }
    }

    private func enrich(_ identities: [WindowIdentity]) {
        let revision = inventoryRefresh.revision
        let observationRevision = inventoryObservationRevision
        // One app-window lookup per batch, rather than one enumeration per WID.
        for group in Dictionary(grouping: identities, by: \.pid).values {
            Task { [weak self] in
                guard let self, self.isMonitoringInventory,
                      self.inventoryRefresh.isCurrent(revision),
                      self.inventoryObservationRevision == observationRevision else { return }
                await self.environment.accessibility.enrichments(for: group) { [weak self] identity, patch in
                    guard let self, self.isMonitoringInventory, self.inventoryRefresh.isCurrent(revision),
                          self.inventoryObservationRevision == observationRevision else { return }
                    self.run(await self.environment.engine.receiveInventory(.semanticsChanged(identity, patch)))
                }
            }
        }
    }

    private func scheduleInventoryRefresh(_ mode: InventoryRefreshMode) {
        guard isMonitoringInventory else { return }
        if mode == .replace {
            run(environment.engine.invalidateActiveSpace())
            semanticInvalidationTasks.values.forEach { $0.cancel() }
            semanticInvalidationTasks.removeAll()
            environment.accessibility.cancelPendingEnrichment()
        }
        inventoryRefresh.request(mode)
    }

    private func applyInventoryRefresh(
        _ snapshot: WindowServerSnapshot?, mode: InventoryRefreshMode, revision: UInt64
    ) async {
        guard isMonitoringInventory, inventoryRefresh.isCurrent(revision) else { return }
        guard let snapshot else {
            receive(.windowServerChanged(.unavailable))
            return
        }
        let event: InventoryEvent = mode == .replace
            ? .replaceActiveSpace(snapshot) : .reconcileActiveSpace(snapshot)
        let effects = await environment.engine.receiveInventory(event)
        guard isMonitoringInventory, inventoryRefresh.isCurrent(revision) else { return }
        let generation = await environment.engine.inventorySnapshot().generation
        guard isMonitoringInventory, inventoryRefresh.isCurrent(revision) else { return }
        inventoryGeneration = generation
        guard environment.windowServer.acceptInventorySnapshot(snapshot, generation: generation) else {
            receive(.windowServerChanged(.unavailable))
            return
        }
        if mode == .replace { environment.engine.activeSpaceRefreshCompleted() }
        run(effects)
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
