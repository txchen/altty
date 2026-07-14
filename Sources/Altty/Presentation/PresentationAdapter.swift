import AppKit

@MainActor
protocol PresentationAdapter: AnyObject {
    func install(onCommand: @escaping (SwitcherCommand) -> Void)
    func installSwitcherInteractions(onInteraction: @escaping (SwitcherSessionEvent) -> Void)
    func update(state: SwitcherPresentationState)
    func presentSettings(state: SwitcherPresentationState)
    func showSwitcherPanel(state: SwitcherPanelState)
    func updateSwitcherPanel(state: SwitcherPanelState)
    func dismissSwitcherPanel()
    func presentSwitchingError(_ error: SwitchingError)
    func openReleasesPage()
}

@MainActor
final class AppKitPresentationAdapter: PresentationAdapter {
    private let exceptions: any ExceptionsAdapter
    private var onCommand: ((SwitcherCommand) -> Void)?
    private var switchingErrorPanel: NSPanel?
    private lazy var menuBar = MenuBarController { [weak self] command in self?.onCommand?(command) }
    private lazy var settings = SettingsWindowController(exceptions: exceptions) {
        [weak self] command in self?.onCommand?(command)
    }
    private lazy var switcherPanel = SwitcherPanelController()

    init(exceptions: any ExceptionsAdapter) {
        self.exceptions = exceptions
    }

    func install(onCommand: @escaping (SwitcherCommand) -> Void) {
        self.onCommand = onCommand
        menuBar.install()
    }

    func installSwitcherInteractions(onInteraction: @escaping (SwitcherSessionEvent) -> Void) {
        switcherPanel.onInteraction = onInteraction
    }

    func update(state: SwitcherPresentationState) {
        menuBar.update(state: state)
        settings.update(state: state)
    }

    func presentSettings(state: SwitcherPresentationState) { settings.show(state: state) }

    func showSwitcherPanel(state: SwitcherPanelState) { switcherPanel.show(state: state) }

    func updateSwitcherPanel(state: SwitcherPanelState) { switcherPanel.update(state: state) }

    func dismissSwitcherPanel() { switcherPanel.dismiss() }

    func presentSwitchingError(_: SwitchingError) {
        switchingErrorPanel?.orderOut(nil)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let background = NSVisualEffectView(frame: panel.contentView!.bounds)
        background.autoresizingMask = [.width, .height]
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12

        let label = NSTextField(labelWithString: "Unable to switch to that window")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            ))
        }
        switchingErrorPanel = panel
        panel.orderFrontRegardless()

        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(2))
            panel?.orderOut(nil)
            if self?.switchingErrorPanel === panel { self?.switchingErrorPanel = nil }
        }
    }

    func openReleasesPage() {
        guard let url = URL(string: "https://github.com/txchen/altty/releases") else { return }
        NSWorkspace.shared.open(url)
    }
}
