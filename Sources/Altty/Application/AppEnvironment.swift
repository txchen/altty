import Foundation

@MainActor
struct AppEnvironment {
    let engine: SwitcherEngine
    let input: any InputAdapter
    let mouseScroll: any MouseScrollAdapter
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
        let workspace = SystemWorkspaceAdapter()
        let launchAtLogin = SystemLaunchAtLoginAdapter()
        let launchAtLoginStatus = launchAtLogin.status
        let generalSettings = GeneralSettings(
            launchAtLogin: launchAtLoginStatus == .enabled,
            listPresentation: settings.snapshot.general.listPresentation,
            reverseMouseWheel: settings.snapshot.general.reverseMouseWheel
        )
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
