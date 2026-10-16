import AppKit

enum MouseHUDState: Equatable {
    case movement(MouseSpeed)
    case scanning
    case picking

    var title: String {
        switch self {
        case .movement(let speed): speed.rawValue.capitalized
        case .scanning: "Finding hints…"
        case .picking: "Type a label to move"
        }
    }
    var controls: String {
        switch self {
        case .movement: "WASD Move    U Slow    I Fast    J Left click    K Right click"
        case .scanning: "Finding targets · You can start typing a label"
        case .picking: "Type a label to move · Backspace Edit"
        }
    }
    var back: String {
        switch self {
        case .movement: "F Hints    Esc Exit"
        case .scanning, .picking: "Esc Mouse Mode"
        }
    }
}

@MainActor
protocol MouseHUD: AnyObject {
    func show(state: MouseHUDState, shortcut: String)
    func hide()
}

@MainActor
final class MouseHUDView: NSVisualEffectView {
    private let title = NSTextField(labelWithString: "")
    private let keys = NSTextField(labelWithString: "")
    private let exit = NSTextField(labelWithString: "")
    private let shortcut: String
    init(state: MouseHUDState, shortcut: String) {
        self.shortcut = shortcut
        super.init(frame: CGRect(x: 0, y: 0, width: 410, height: 104))
        material = .hudWindow
        blendingMode = .behindWindow
        self.state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        title.font = .boldSystemFont(ofSize: 15)
        keys.font = .systemFont(ofSize: 12)
        exit.font = .systemFont(ofSize: 12)
        exit.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, keys, exit])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update(state: state)
    }
    required init?(coder: NSCoder) { nil }
    func update(state: MouseHUDState) {
        let value = "Mouse Mode · \(state.title)"
        if title.stringValue != value { title.stringValue = value }
        if keys.stringValue != state.controls { keys.stringValue = state.controls }
        let exitValue = "\(state.back)    \(shortcut) Exit"
        if exit.stringValue != exitValue { exit.stringValue = exitValue }
    }
}

@MainActor
final class PanelMouseHUD: MouseHUD {
    private var panel: NSPanel?
    func show(state: MouseHUDState, shortcut: String) {
        if let panel, let view = panel.contentView as? MouseHUDView {
            view.update(state: state)
            position(panel)
            return
        }
        let view = MouseHUDView(state: state, shortcut: shortcut)
        let panel = MouseHUDPanel(
            contentRect: view.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        position(panel)
        self.panel = panel
        panel.orderFrontRegardless()
    }
    private func position(_ panel: NSPanel) {
        let point = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            let origin = CGPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.minY + 24)
            if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        }
    }
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class MouseHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
