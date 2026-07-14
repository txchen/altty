import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.presentation.install { [weak self] command in self?.handle(command) }
        handle(.launch)
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
            case .presentSettings:
                environment.presentation.presentSettings(state: environment.engine.presentationState)
            case .requestAccessibility:
                environment.accessibility.requestPermission()
                receive(.accessibilityChanged(environment.accessibility.availability()))
            case .openReleasesPage:
                environment.presentation.openReleasesPage()
            case .terminate:
                NSApp.terminate(nil)
            }
        }
    }

    private func refreshPresentation() {
        let state = environment.engine.presentationState
        environment.presentation.update(state: state)
    }
}
