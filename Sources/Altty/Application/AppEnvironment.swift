import Foundation

@MainActor
struct AppEnvironment {
    let engine: SwitcherEngine
    let input: any InputAdapter
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
        let generalSettings = GeneralSettings(
            launchAtLogin: launchAtLogin.isEnabled,
            listPresentation: settings.snapshot.general.listPresentation
        )
        return AppEnvironment(
            engine: SwitcherEngine(
                inventory: inventory,
                shortcuts: settings.snapshot.shortcuts,
                exceptionRules: settings.snapshot.exceptionRules,
                generalSettings: generalSettings,
                settingsWarning: settings.warning?.message
            ),
            input: SystemInputAdapter(shortcuts: settings.snapshot.shortcuts),
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
