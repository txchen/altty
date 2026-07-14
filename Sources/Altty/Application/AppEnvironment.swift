import Foundation

@MainActor
struct AppEnvironment {
    let engine: SwitcherEngine
    let input: any InputAdapter
    let windowServer: any WindowServerAdapter
    let accessibility: any AccessibilityAdapter
    let inventory: any InventoryAdapter
    let switching: any SwitchingAdapter
    let exceptions: any ExceptionsAdapter
    let persistence: any PersistenceAdapter
    let presentation: any PresentationAdapter
    let diagnostics: any DiagnosticsAdapter

    static func production() -> AppEnvironment {
        AppEnvironment(
            engine: SwitcherEngine(),
            input: SystemInputAdapter(),
            windowServer: SystemWindowServerAdapter(),
            accessibility: SystemAccessibilityAdapter(),
            inventory: WindowInventory(),
            switching: SystemSwitchingAdapter(),
            exceptions: DefaultExceptionsAdapter(),
            persistence: UserDefaultsPersistenceAdapter(),
            presentation: AppKitPresentationAdapter(),
            diagnostics: UnifiedLogDiagnosticsAdapter()
        )
    }
}
