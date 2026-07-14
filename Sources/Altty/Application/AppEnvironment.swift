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
    let persistence: any PersistenceAdapter
    let presentation: any PresentationAdapter
    let diagnostics: any DiagnosticsAdapter

    static func production() -> AppEnvironment {
        let inventory = WindowInventory()
        let persistence = FileSettingsPersistenceAdapter()
        let settings = persistence.loadSettings()
        return AppEnvironment(
            engine: SwitcherEngine(
                inventory: inventory,
                shortcuts: settings.snapshot.shortcuts,
                settingsWarning: settings.warning?.message
            ),
            input: SystemInputAdapter(shortcuts: settings.snapshot.shortcuts),
            windowServer: SystemWindowServerAdapter(),
            accessibility: SystemAccessibilityAdapter(),
            workspace: SystemWorkspaceAdapter(),
            inventory: inventory,
            switching: SystemSwitchingAdapter(),
            exceptions: DefaultExceptionsAdapter(),
            persistence: persistence,
            presentation: AppKitPresentationAdapter(),
            diagnostics: UnifiedLogDiagnosticsAdapter()
        )
    }
}
