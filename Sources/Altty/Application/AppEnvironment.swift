import Foundation

@MainActor
struct AppEnvironment {
    let engine: SwitcherEngine
    let input: any InputAdapter
    let mouseScroll: any MouseScrollAdapter
    let hintShortcut: any HintShortcutAdapter
    let hints: any HintSessionController
    var mouseShortcut: (any HintShortcutAdapter)? = nil
    var mouse: SystemMouseSessionController? = nil
    let windowServer: any WindowServerAdapter
    let accessibility: any AccessibilityAdapter
    let workspace: any WorkspaceAdapter
    let inventory: any InventoryAdapter
    let switching: any SwitchingAdapter
    let exceptions: any ExceptionsAdapter
    let launchAtLogin: any LaunchAtLoginAdapter
    let persistence: any PersistenceAdapter
    let presentation: any PresentationAdapter
    let diagnostics: any DiagnosticsAdapter

    static func production() -> AppEnvironment {
        let inventory = WindowInventory()
        let persistence = FileSettingsPersistenceAdapter()
        let settings = persistence.loadSettings()
        DiagnosticLogging.shared.setEnabled(settings.snapshot.general.diagnosticLoggingEnabled)
        let workspace = SystemWorkspaceAdapter()
        let launchAtLogin = SystemLaunchAtLoginAdapter()
        let launchAtLoginStatus = launchAtLogin.status
        let generalSettings = GeneralSettings(
            launchAtLogin: launchAtLoginStatus == .enabled,
            listPresentation: settings.snapshot.general.listPresentation,
            reverseMouseWheel: settings.snapshot.general.reverseMouseWheel,
            diagnosticLoggingEnabled: settings.snapshot.general.diagnosticLoggingEnabled,
            hintMode: settings.snapshot.general.hintMode,
            mouseMode: settings.snapshot.general.mouseMode
        )
        let navigationTap = CoreGraphicsHintKeyboardTap()
        return AppEnvironment(
            engine: SwitcherEngine(
                inventory: inventory,
                shortcuts: settings.snapshot.shortcuts,
                exceptionRules: settings.snapshot.exceptionRules,
                generalSettings: generalSettings,
                launchAtLoginRequiresApproval: launchAtLoginStatus == .requiresApproval,
                settingsWarning: settings.warning?.message
            ),
            input: SystemInputAdapter(shortcuts: settings.snapshot.shortcuts),
            mouseScroll: SystemMouseScrollAdapter(),
            hintShortcut: CarbonHintShortcutAdapter(),
            hints: SystemHintSessionController(tap: navigationTap),
            mouseShortcut: CarbonHintShortcutAdapter(signature: 0x414C544D),
            mouse: SystemMouseSessionController(tap: navigationTap),
            windowServer: SystemWindowServerAdapter(),
            accessibility: SystemAccessibilityAdapter(),
            workspace: workspace,
            inventory: inventory,
            switching: SystemSwitchingAdapter(),
            exceptions: workspace,
            launchAtLogin: launchAtLogin,
            persistence: persistence,
            presentation: AppKitPresentationAdapter(exceptions: workspace),
            diagnostics: UnifiedLogDiagnosticsAdapter()
        )
    }
}
