import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment
    private var isMonitoringInventory = false
    private var pendingInventoryRefresh: InventoryRefreshMode?
    private var inventoryRefreshTask: Task<Void, Never>?
    private var inventoryRefreshSequence: UInt64 = 0
    private var inventoryGeneration: InventoryGeneration = 0
    private var semanticInvalidationTasks: [WindowIdentity: Task<Void, Never>] = [:]
    private var shortcutInvocationTask: Task<Void, Never>?
    private var switcherPanelTask: Task<Void, Never>?

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
        switcherPanelTask?.cancel()
        environment.presentation.dismissSwitcherPanel()
        environment.input.setShortcutsEnabled(false)
        stopInventoryObservation()
        environment.accessibility.stopMonitoringAvailability()
        environment.accessibility.releaseObservers()
    }

    private func handle(_ command: SwitcherCommand) {
        run(environment.engine.send(command))
        refreshPresentation()
    }

    private func receive(_ event: SwitcherEvent) {
        run(environment.engine.receive(event))
        refreshPresentation()
    }

    private func receive(_ event: ShortcutEvent) {
        switch event {
        case let .allWindowsPressed(direction):
            let priorInvocation = shortcutInvocationTask
            shortcutInvocationTask = Task { [weak self] in
                await priorInvocation?.value
                guard let self else { return }
                if self.environment.engine.activeSwitchSession == nil {
                    self.run(await self.environment.engine.beginAllWindowsSwitch(
                        direction: direction
                    ))
                } else {
                    self.run(self.environment.engine.receiveSession(.navigate(direction)))
                }
                self.refreshPresentation()
            }
        case .holdModifiersReleased:
            let invocation = shortcutInvocationTask
            shortcutInvocationTask = nil
            Task { [weak self] in
                await invocation?.value
                guard let self else { return }
                self.run(self.environment.engine.confirmAllWindowsSwitch())
                self.refreshPresentation()
            }
        case let .cancel(reason):
            let invocation = shortcutInvocationTask
            shortcutInvocationTask = nil
            Task { [weak self] in
                await invocation?.value
                guard let self else { return }
                self.run(self.environment.engine.receiveSession(.cancel(reason)))
            }
        }
    }

    private func receive(_ event: SwitchingEvent) {
        Task { [weak self] in
            guard let self else { return }
            self.run(await self.environment.engine.receiveSwitching(event))
            self.refreshPresentation()
        }
    }

    private func run(_ effects: [SwitcherEffect]) {
        for effect in effects {
            switch effect {
            case .checkAccessibility:
                receive(.accessibilityChanged(environment.accessibility.availability()))
            case .checkWindowServer:
                receive(.windowServerChanged(environment.windowServer.availability()))
            case let .setShortcutsEnabled(enabled):
                environment.input.setShortcutsEnabled(enabled)
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
            case .openReleasesPage:
                environment.presentation.openReleasesPage()
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
                dismissSwitcherPanelForConfirmation()
                Task { [weak self] in
                    guard let self else { return }
                    let succeeded = await self.environment.accessibility.deminimize(identity)
                    self.receive(.deminimizeCompleted(identity, succeeded: succeeded))
                }
            case let .focusWindow(identity):
                dismissSwitcherPanelForConfirmation()
                focusTarget(identity)
            case let .verifyFocus(identity):
                verifyFocus(identity)
            case let .recoverFailedFocus(target, origin):
                recoverFailedFocus(target: target, origin: origin)
            case let .presentSwitchingError(error):
                environment.presentation.presentSwitchingError(error)
            case let .scheduleSwitcherPanel(delayMilliseconds):
                scheduleSwitcherPanel(delayMilliseconds: delayMilliseconds)
            case let .showSwitcherPanel(state):
                environment.presentation.showSwitcherPanel(state: state)
            case let .updateSwitcherPanel(state):
                environment.presentation.updateSwitcherPanel(state: state)
            }
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

    private func focusTarget(_ identity: WindowIdentity) {
        Task { [weak self] in
            guard let self else { return }
            let succeeded = await self.environment.windowServer.focus(identity)
            self.receive(.focusCompleted(identity, succeeded: succeeded))
        }
    }

    private func recoverFailedFocus(target: WindowIdentity, origin: WindowIdentity?) {
        Task { [weak self] in
            guard let self else { return }
            if let origin { _ = await self.environment.windowServer.focus(origin) }
            try? await Task.sleep(for: .milliseconds(100))
            self.receive(.failedFocusRecoveryCompleted(target))
        }
    }

    private func verifyFocus(_ identity: WindowIdentity) {
        Task { [weak self] in
            guard let self else { return }
            var observed: FocusedWindow?
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(25))
                observed = await self.environment.accessibility.focusedWindow()
                if observed == FocusedWindow(wid: identity.wid, pid: identity.pid) { break }
            }
            self.receive(.focusPostconditionObserved(observed))
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
        pendingInventoryRefresh = nil
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
        if mode == .replace || pendingInventoryRefresh == nil {
            pendingInventoryRefresh = mode
        }
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
                  let mode = self.pendingInventoryRefresh else { return }
            self.pendingInventoryRefresh = nil
            guard let snapshot = await self.environment.windowServer.activeSpaceSnapshot() else { return }
            guard !Task.isCancelled, self.isMonitoringInventory,
                  sequence == self.inventoryRefreshSequence else { return }
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

    @objc private func systemDidWake() { handle(.systemDidWake) }
}
