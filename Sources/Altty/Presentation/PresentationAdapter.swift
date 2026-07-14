import AppKit

@MainActor
protocol PresentationAdapter: AnyObject {
    func install(onCommand: @escaping (SwitcherCommand) -> Void)
    func update(state: SwitcherPresentationState)
    func presentSettings(state: SwitcherPresentationState)
    func openReleasesPage()
}

@MainActor
final class AppKitPresentationAdapter: PresentationAdapter {
    private var onCommand: ((SwitcherCommand) -> Void)?
    private lazy var menuBar = MenuBarController { [weak self] command in self?.onCommand?(command) }
    private lazy var settings = SettingsWindowController { [weak self] command in self?.onCommand?(command) }

    func install(onCommand: @escaping (SwitcherCommand) -> Void) {
        self.onCommand = onCommand
        menuBar.install()
    }

    func update(state: SwitcherPresentationState) {
        menuBar.update(state: state)
        settings.update(state: state)
    }

    func presentSettings(state: SwitcherPresentationState) { settings.show(state: state) }

    func openReleasesPage() {
        guard let url = URL(string: "https://github.com/txchen/altty/releases") else { return }
        NSWorkspace.shared.open(url)
    }
}
