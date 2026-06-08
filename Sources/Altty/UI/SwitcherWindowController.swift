import AppKit
import Carbon.HIToolbox

final class SwitcherWindowController: NSWindowController {
    var onFocus: ((WindowItem) -> Void)?

    private let content = NSVisualEffectView()
    private let stackView = NSStackView()
    private var windows = [WindowItem]()
    private var rowViews = [WindowRowView]()
    private var selectedIndex = 0

    var isVisible: Bool {
        window?.isVisible == true
    }

    init() {
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.onMoveSelection = { [weak self] delta in self?.moveSelection(delta) }
        panel.onConfirm = { [weak self] in self?.focusSelectionIfVisible() }
        panel.onCancel = { [weak self] in self?.hide() }
        configureContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(windows: [WindowItem]) {
        self.windows = windows
        selectedIndex = windows.count > 1 ? 1 : 0
        rebuildRows()
        resizePanel()
        centerOnActiveScreen()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectNext() {
        moveSelection(1)
    }

    func focusSelectionIfVisible() {
        guard isVisible, windows.indices.contains(selectedIndex) else { return }
        let selected = windows[selectedIndex]
        hide()
        onFocus?(selected)
    }

    private func configureContent() {
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 14

        stackView.orientation = .vertical
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stackView)
        window?.contentView = content
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: content.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func rebuildRows() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowViews = windows.map { item in
            let row = WindowRowView()
            row.configure(with: item)
            stackView.addArrangedSubview(row)
            return row
        }
        updateSelection()
    }

    private func resizePanel() {
        let visibleRows = min(windows.count, 8)
        let height = CGFloat(visibleRows * 58 + 20)
        window?.setContentSize(NSSize(width: 620, height: max(90, height)))
    }

    private func centerOnActiveScreen() {
        guard let window else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            window.center()
            return
        }
        let origin = NSPoint(
            x: frame.midX - window.frame.width * 0.5,
            y: frame.midY - window.frame.height * 0.5
        )
        window.setFrameOrigin(origin)
    }

    private func moveSelection(_ delta: Int) {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + windows.count) % windows.count
        updateSelection()
    }

    private func updateSelection() {
        for (index, row) in rowViews.enumerated() {
            row.isSelected = index == selectedIndex
        }
    }

    private func hide() {
        window?.orderOut(nil)
    }
}
