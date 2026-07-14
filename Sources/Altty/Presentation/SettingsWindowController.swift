import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private struct Pane: Equatable {
        let title: String
        let symbol: String
        let detail: String

        static let general = Pane(title: "General", symbol: "gearshape", detail: "Altty remains available from the menu bar while required system access is unavailable.")
        static let shortcuts = Pane(title: "Shortcuts", symbol: "keyboard", detail: "Shortcut configuration will be available in a later build.")
        static let exceptions = Pane(title: "Exceptions", symbol: "list.bullet.rectangle", detail: "Application exception rules will be available in a later build.")
        static let about = Pane(title: "About", symbol: "info.circle", detail: "Altty is a private, title-list window switcher for macOS 15.")
        static let all = [general, shortcuts, exceptions, about]
    }

    private let onRecheck: () -> Void
    private let statusLabel = NSTextField(labelWithString: "Starting…")
    private let contentContainer = NSView()
    private let sidebar = NSTableView()

    init(onRecheck: @escaping () -> Void) {
        self.onRecheck = onRecheck
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Altty Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureSidebar(on: window)
        showPane(.general)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(state: SwitcherPresentationState) {
        update(state: state)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(state: SwitcherPresentationState) { statusLabel.stringValue = state.readinessTitle }

    private func configureSidebar(on window: NSWindow) {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        sidebar.addTableColumn(NSTableColumn(identifier: .init("Pane")))
        sidebar.headerView = nil
        sidebar.rowHeight = 32
        sidebar.style = .sourceList
        sidebar.dataSource = self
        sidebar.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = sidebar
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .windowBackgroundColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(scroll)
        split.addArrangedSubview(contentContainer)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        window.contentView = split
        scroll.widthAnchor.constraint(equalToConstant: 176).isActive = true
        sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { Pane.all.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let pane = Pane.all[row]
        let cell = NSTableCellView()
        let label = NSButton(title: pane.title, image: NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title) ?? NSImage(), target: nil, action: nil)
        label.isBordered = false
        label.imagePosition = .imageLeading
        label.alignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard sidebar.selectedRow >= 0 else { return }
        showPane(Pane.all[sidebar.selectedRow])
    }

    private func showPane(_ pane: Pane) {
        let root = NSView()
        let title = NSTextField(labelWithString: pane.title)
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: pane.detail)
        detail.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, detail])
        if pane == .general {
            statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
            stack.addArrangedSubview(statusLabel)
            let button = NSButton(title: "Check Readiness", target: self, action: #selector(recheck))
            stack.addArrangedSubview(button)
        }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
        ])
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        root.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    @objc private func recheck() { onRecheck() }
}
