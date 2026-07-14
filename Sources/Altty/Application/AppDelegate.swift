import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment
    private var isMonitoringInventory = false
    private var pendingInventoryRefresh: InventoryRefreshMode?
    private var inventoryRefreshTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.presentation.install { [weak self] command in self?.handle(command) }
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
                }
            }
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
        pendingInventoryRefresh = nil
        environment.windowServer.stopMonitoringInventory()
        environment.accessibility.stopMonitoringInventory()
        environment.workspace.stopMonitoring()
    }

    private func receive(_ event: WindowServerInventoryEvent) {
        switch event {
        case .created, .destroyed:
            scheduleInventoryRefresh(.reconcile)
        case let .focused(wid):
            Task { [weak self] in
                guard let self,
                      let identity = await self.environment.engine.inventoryIdentity(for: wid) else { return }
                self.run(await self.environment.engine.receiveInventory(.focused(identity)))
            }
        case let .semanticsInvalidated(wid):
            invalidateSemantics(wid: wid, pid: nil)
        case .activeSpaceChanged:
            scheduleInventoryRefresh(.replace)
        }
    }

    private func receive(_ event: AccessibilityInventoryEvent) {
        switch event {
        case .created, .destroyed:
            scheduleInventoryRefresh(.reconcile)
        case let .focused(pid, wid):
            if let wid { invalidateSemantics(wid: wid, pid: pid) }
        case let .semanticsChanged(pid, wid):
            if let wid { invalidateSemantics(wid: wid, pid: pid) }
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

    private func invalidateSemantics(wid: WindowID, pid: ProcessID?) {
        Task { [weak self] in
            guard let self,
                  let identity = await self.environment.engine.inventoryIdentity(for: wid, pid: pid) else {
                return
            }
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
            let event: InventoryEvent = mode == .replace
                ? .replaceActiveSpace(snapshot)
                : .reconcileActiveSpace(snapshot)
            self.run(await self.environment.engine.receiveInventory(event))
        }
    }

    private func refreshPresentation() {
        let state = environment.engine.presentationState
        environment.presentation.update(state: state)
    }

    @objc private func systemDidWake() { handle(.systemDidWake) }
}
