import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Darwin
@testable import Altty

private struct FocusSmokeConfiguration {
    let keyCode: CGKeyCode
    let pressCount: Int
    let pid: ProcessID
    let wids: [WindowID]

    var origin: WindowIdentity {
        WindowIdentity(wid: wids[0], pid: pid, generation: 1)
    }

    var target: WindowIdentity {
        WindowIdentity(wid: wids[pressCount], pid: pid, generation: 1)
    }

    init?() {
        guard CommandLine.arguments.count == 4,
              let keyCode = CGKeyCode(CommandLine.arguments[1]),
              let minimumWindowCount = Int(CommandLine.arguments[2]),
              let pressCount = Int(CommandLine.arguments[3]),
              let pidText = ProcessInfo.processInfo.environment["ALTTY_FOCUS_FIXTURE_PID"],
              let pid = ProcessID(pidText),
              let widText = ProcessInfo.processInfo.environment["ALTTY_FOCUS_FIXTURE_WIDS"] else {
            return nil
        }
        let wids = widText.split(separator: ",").compactMap { WindowID($0) }
        guard wids.count >= minimumWindowCount,
              pressCount > 0,
              pressCount < wids.count,
              Set(wids).count == wids.count else {
            return nil
        }
        self.keyCode = keyCode
        self.pressCount = pressCount
        self.pid = pid
        self.wids = wids
    }
}

@MainActor
private final class ControlledWindowServerAdapter: WindowServerAdapter {
    private let system = SystemWindowServerAdapter()
    private let controlledSnapshot: WindowServerSnapshot

    init(configuration: FocusSmokeConfiguration) {
        controlledSnapshot = WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: configuration.wids.enumerated().map { index, wid in
                WindowServerWindow(
                    wid: wid,
                    pid: configuration.pid,
                    frontToBackOrder: index
                )
            }
        )
    }

    func availability() -> Availability { system.availability() }

    func activeSpaceSnapshot() async -> WindowServerSnapshot? { controlledSnapshot }

    func actualActiveSpaceSnapshot() async -> WindowServerSnapshot? {
        await system.activeSpaceSnapshot()
    }

    func focus(_ identity: WindowIdentity) async -> Bool { await system.focus(identity) }

    func startMonitoringActiveSpace(_: @escaping @MainActor () -> Void) {}

    func stopMonitoringActiveSpace() {}

    func startMonitoringInventory(
        _: @escaping @MainActor (WindowServerInventoryEvent) -> Void
    ) {}

    func stopMonitoringInventory() {}

    func acceptInventorySnapshot(
        _: WindowServerSnapshot,
        generation _: InventoryGeneration
    ) -> Bool { true }
}

@MainActor
private final class FocusSmokeWorkspaceAdapter: WorkspaceAdapter {
    private let facts: WorkspaceApplicationFacts
    private let application: ExceptionApplication

    init(pid: ProcessID) {
        facts = WorkspaceApplicationFacts(
            pid: pid,
            bundleIdentifier: "app.altty.focus-fixture",
            applicationName: "Altty Focus Fixture",
            isHidden: false,
            isFrontmost: true
        )
        application = ExceptionApplication(
            bundleIdentifier: "app.altty.focus-fixture",
            name: "Altty Focus Fixture",
            bundlePath: nil
        )
    }

    func runningApplications() -> [WorkspaceApplicationFacts] { [facts] }

    func startMonitoring(_: @escaping @MainActor (WorkspaceApplicationEvent) -> Void) {}

    func stopMonitoring() {}

    func runningExceptionApplications() -> [ExceptionApplication] { [application] }

    func exceptionApplication(bundleIdentifier: String) -> ExceptionApplication? {
        bundleIdentifier == application.bundleIdentifier ? application : nil
    }

    func exceptionApplication(at _: URL) -> ExceptionApplication? { nil }

    func frontmostApplicationBundleIdentifier() -> String? { application.bundleIdentifier }
}

@MainActor
private final class FocusSmokePresentationAdapter: PresentationAdapter {
    func install(onCommand _: @escaping (SwitcherCommand) -> Void) {}
    func installSwitcherInteractions(onInteraction _: @escaping (SwitcherSessionEvent) -> Void) {}
    func update(state _: SwitcherPresentationState) {}
    func presentSettings(state _: SwitcherPresentationState) {}
    func showSwitcherPanel(state _: SwitcherPanelState) {}
    func updateSwitcherPanel(state _: SwitcherPanelState) {}
    func dismissSwitcherPanel() {}
    func presentSwitchingError(_: SwitchingError) {}
    func openExternalPage(_: ExternalPage) {}
}

@MainActor
private final class FocusSmokeLaunchAtLoginAdapter: LaunchAtLoginAdapter {
    var status = LaunchAtLoginStatus.disabled

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        status = enabled ? .enabled : .disabled
        return status
    }

    func openSystemSettings() {}
}

private struct FocusSmokePersistenceAdapter: PersistenceAdapter {
    func loadSettings() -> SettingsLoadResult {
        SettingsLoadResult(snapshot: .defaults, warning: nil)
    }

    func saveSettings(_: SettingsSnapshot) throws {}
}

private struct FocusSmokeDiagnosticsAdapter: DiagnosticsAdapter {
    func record(_: DiagnosticEvent) {}
}

@MainActor
private final class FocusSmokeObserver {
    private let configuration: FocusSmokeConfiguration
    private let engine: SwitcherEngine
    private let input: SystemInputAdapter
    private let windowServer: ControlledWindowServerAdapter
    private let accessibility: SystemAccessibilityAdapter
    private var finishing = false

    init(
        configuration: FocusSmokeConfiguration,
        engine: SwitcherEngine,
        input: SystemInputAdapter,
        windowServer: ControlledWindowServerAdapter,
        accessibility: SystemAccessibilityAdapter
    ) {
        self.configuration = configuration
        self.engine = engine
        self.input = input
        self.windowServer = windowServer
        self.accessibility = accessibility
    }

    func run() async {
        guard await validateFixture(),
              await focusAndObserve(configuration.origin),
              await waitForReadinessAndInventory() else {
            await finish(success: false, message: "Focus fixture did not become ready")
            return
        }

        guard await postShortcut(pressCount: configuration.pressCount),
              await waitForCompletedSwitch(to: configuration.target) else {
            await finish(success: false, message: "Altty did not verify the target focus transaction")
            return
        }

        guard await postShortcut(pressCount: 1),
              await waitForCompletedSwitch(to: configuration.origin) else {
            await finish(success: false, message: "Altty did not verify restoration of the origin")
            return
        }

        await finish(success: true, message: "Immediate focus smoke passed and restored origin")
    }

    private func validateFixture() async -> Bool {
        let snapshot = await windowServer.actualActiveSpaceSnapshot()
        let actualWIDs = Set(snapshot?.windows.filter {
            $0.pid == configuration.pid
        }.map(\.wid) ?? [])
        return Set(configuration.wids).isSubset(of: actualWIDs)
    }

    private func waitForReadinessAndInventory() async -> Bool {
        for _ in 0..<120 {
            let snapshot = await engine.inventorySnapshot()
            if engine.presentationState.isReady,
               snapshot.windows.map(\.wid) == configuration.wids {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    private func waitForCompletedSwitch(to identity: WindowIdentity) async -> Bool {
        for _ in 0..<120 {
            let snapshot = await engine.inventorySnapshot()
            if engine.activeSwitchSession == nil,
               snapshot.windows.first?.wid == identity.wid,
               await accessibility.focusedWindow() == FocusedWindow(
                   wid: identity.wid,
                   pid: identity.pid
               ) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    private func focusAndObserve(_ identity: WindowIdentity) async -> Bool {
        for _ in 0..<3 {
            guard await windowServer.focus(identity) else { continue }
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(25))
                if await accessibility.focusedWindow() == FocusedWindow(
                    wid: identity.wid,
                    pid: identity.pid
                ) {
                    return true
                }
            }
        }
        return false
    }

    private func postShortcut(pressCount: Int) async -> Bool {
        guard postKey(CGKeyCode(kVK_Option), keyDown: true, flags: .maskAlternate) else {
            return false
        }
        try? await Task.sleep(for: .milliseconds(50))
        for _ in 0..<pressCount {
            guard postKey(configuration.keyCode, keyDown: true, flags: .maskAlternate),
                  postKey(configuration.keyCode, keyDown: false, flags: .maskAlternate) else {
                return false
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return postKey(CGKeyCode(kVK_Option), keyDown: false, flags: [])
    }

    private func postKey(
        _ keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) -> Bool {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else { return false }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }

    private func finish(success: Bool, message: String) async {
        guard !finishing else { return }
        finishing = true
        _ = input.setShortcutsEnabled(false)
        if !success { _ = await focusAndObserve(configuration.origin) }
        let stream = success ? FileHandle.standardOutput : FileHandle.standardError
        try? stream.write(contentsOf: Data("\(message)\n".utf8))
        Darwin.exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}

@main
@MainActor
private enum ImmediateFocusSmokeProbe {
    static func main() {
        guard let configuration = FocusSmokeConfiguration() else {
            try? FileHandle.standardError.write(
                contentsOf: Data("Missing or invalid focus-smoke configuration\n".utf8)
            )
            Darwin.exit(EXIT_FAILURE)
        }

        let inventory = WindowInventory()
        let engine = SwitcherEngine(inventory: inventory)
        let input = SystemInputAdapter()
        let windowServer = ControlledWindowServerAdapter(configuration: configuration)
        let accessibility = SystemAccessibilityAdapter()
        let workspace = FocusSmokeWorkspaceAdapter(pid: configuration.pid)
        let environment = AppEnvironment(
            engine: engine,
            input: input,
            mouseScroll: SystemMouseScrollAdapter(),
            hintShortcut: CarbonHintShortcutAdapter(),
            hints: PendingHintSessionController(),
            windowServer: windowServer,
            accessibility: accessibility,
            workspace: workspace,
            inventory: inventory,
            switching: SystemSwitchingAdapter(),
            exceptions: workspace,
            launchAtLogin: FocusSmokeLaunchAtLoginAdapter(),
            persistence: FocusSmokePersistenceAdapter(),
            presentation: FocusSmokePresentationAdapter(),
            diagnostics: FocusSmokeDiagnosticsAdapter()
        )
        let delegate = AppDelegate(environment: environment)
        let observer = FocusSmokeObserver(
            configuration: configuration,
            engine: engine,
            input: input,
            windowServer: windowServer,
            accessibility: accessibility
        )

        let application = NSApplication.shared
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: application,
            queue: .main
        ) { _ in
            Task { @MainActor in await observer.run() }
        }
        withExtendedLifetime((delegate, observer, token)) {
            application.run()
        }
    }
}
