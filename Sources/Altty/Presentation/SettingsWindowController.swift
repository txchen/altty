import AppKit
import Carbon

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private struct Pane: Equatable {
        let title: String
        let symbol: String
        let detail: String

        static let general = Pane(title: "General", symbol: "gearshape", detail: "Altty remains available from the menu bar while required system access is unavailable.")
        static let shortcuts = Pane(title: "Shortcuts", symbol: "keyboard", detail: "Choose one shortcut per switcher. Hold Shift with either shortcut to navigate in reverse.")
        static let exceptions = Pane(title: "Exceptions", symbol: "list.bullet.rectangle", detail: "Application exception rules will be available in a later build.")
        static let about = Pane(title: "About", symbol: "info.circle", detail: "Altty is a private, title-list window switcher for macOS 15.")
        static let all = [general, shortcuts, exceptions, about]
    }

    private let onCommand: (SwitcherCommand) -> Void
    private let statusLabel = NSTextField(labelWithString: "Starting…")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "Accessibility: Checking…")
    private let accessibilityDetailLabel = NSTextField(wrappingLabelWithString: "Checking Accessibility permission.")
    private let skyLightStatusLabel = NSTextField(labelWithString: "SkyLight: Checking…")
    private let skyLightDetailLabel = NSTextField(wrappingLabelWithString: "Checking WindowServer capability.")
    private let accessibilityButton = NSButton(title: "Grant Accessibility…", target: nil, action: #selector(requestAccessibility))
    private let recheckButton = NSButton(title: "Check Readiness", target: nil, action: #selector(recheck))
    private let contentContainer = NSView()
    private let sidebar = NSTableView()
    private let shortcutErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let shortcutPendingLabel = NSTextField(labelWithString: "")
    private lazy var allWindowsRecorder = ShortcutRecorderControl(
        mode: .allWindows,
        binding: ShortcutPair.defaults.allWindows
    ) { [weak self] mode, binding in
        self?.onCommand(.updateShortcut(mode, binding))
    }
    private lazy var currentAppRecorder = ShortcutRecorderControl(
        mode: .currentApp,
        binding: ShortcutPair.defaults.currentApp
    ) { [weak self] mode, binding in
        self?.onCommand(.updateShortcut(mode, binding))
    }

    init(onCommand: @escaping (SwitcherCommand) -> Void) {
        self.onCommand = onCommand
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Altty Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        accessibilityButton.target = self
        recheckButton.target = self
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

    func update(state: SwitcherPresentationState) {
        statusLabel.stringValue = state.readinessTitle
        accessibilityStatusLabel.stringValue = state.accessibilityStatusTitle
        accessibilityDetailLabel.stringValue = state.accessibilityDetail
        skyLightStatusLabel.stringValue = state.skyLightStatusTitle
        skyLightDetailLabel.stringValue = state.skyLightDetail
        accessibilityButton.isHidden = !state.showsAccessibilityAction
        updateShortcuts(state.shortcutSettings)
    }

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
            statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            accessibilityStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
            accessibilityDetailLabel.textColor = .secondaryLabelColor
            skyLightStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
            skyLightDetailLabel.textColor = .secondaryLabelColor
            stack.addArrangedSubview(statusLabel)
            stack.addArrangedSubview(accessibilityStatusLabel)
            stack.addArrangedSubview(accessibilityDetailLabel)
            stack.addArrangedSubview(accessibilityButton)
            stack.addArrangedSubview(skyLightStatusLabel)
            stack.addArrangedSubview(skyLightDetailLabel)
            stack.addArrangedSubview(recheckButton)
        } else if pane == .shortcuts {
            stack.addArrangedSubview(shortcutRow(
                title: SwitcherMode.allWindows.title,
                recorder: allWindowsRecorder,
                defaultBinding: ShortcutPair.defaults.allWindows
            ))
            stack.addArrangedSubview(shortcutRow(
                title: SwitcherMode.currentApp.title,
                recorder: currentAppRecorder,
                defaultBinding: ShortcutPair.defaults.currentApp
            ))
            shortcutPendingLabel.textColor = .secondaryLabelColor
            shortcutPendingLabel.font = .systemFont(ofSize: 12)
            shortcutErrorLabel.textColor = .systemRed
            shortcutErrorLabel.font = .systemFont(ofSize: 12)
            shortcutErrorLabel.maximumNumberOfLines = 3
            stack.addArrangedSubview(shortcutPendingLabel)
            stack.addArrangedSubview(shortcutErrorLabel)
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

    @objc private func recheck() { onCommand(.recheckReadiness) }
    @objc private func requestAccessibility() { onCommand(.requestAccessibility) }

    private func shortcutRow(
        title: String,
        recorder: ShortcutRecorderControl,
        defaultBinding: ShortcutBinding
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let defaultLabel = NSTextField(
            labelWithString: "Default: \(defaultBinding.displayName)"
        )
        defaultLabel.textColor = .secondaryLabelColor
        defaultLabel.font = .systemFont(ofSize: 11)
        let labels = NSStackView(views: [titleLabel, defaultLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let row = NSStackView(views: [labels, recorder])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 20
        labels.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return row
    }

    private func updateShortcuts(_ state: ShortcutSettingsState) {
        let displayed = state.pending ?? state.current
        allWindowsRecorder.setBinding(displayed.allWindows)
        currentAppRecorder.setBinding(displayed.currentApp)
        shortcutPendingLabel.stringValue = state.pending == nil
            ? ""
            : "This change will take effect when the current switcher session ends."
        shortcutPendingLabel.isHidden = state.pending == nil
        shortcutErrorLabel.stringValue = state.inlineMessage ?? ""
        shortcutErrorLabel.isHidden = state.inlineMessage == nil
    }
}

@MainActor
final class ShortcutRecorderControl: NSButton {
    private let mode: SwitcherMode
    private let onBinding: (SwitcherMode, ShortcutBinding) -> Void
    private var binding: ShortcutBinding
    private var isRecording = false

    init(
        mode: SwitcherMode,
        binding: ShortcutBinding,
        onBinding: @escaping (SwitcherMode, ShortcutBinding) -> Void
    ) {
        self.mode = mode
        self.binding = binding
        self.onBinding = onBinding
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setBinding(binding)
        toolTip = "Click, then type the new \(mode.title) shortcut"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    func setBinding(_ binding: ShortcutBinding) {
        self.binding = binding
        guard !isRecording else { return }
        title = binding.displayName
        setAccessibilityLabel("\(mode.title) shortcut, \(binding.displayName)")
    }

    @objc private func beginRecording() {
        isRecording = true
        title = "Type Shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            setBinding(binding)
            return
        }
        let key = ShortcutKey(
            keyCode: UInt32(event.keyCode),
            displayName: Self.keyDisplayName(event)
        )
        let proposed = ShortcutBinding(
            key: key,
            modifiers: ShortcutModifiers(eventFlags: event.modifierFlags)
        )
        isRecording = false
        onBinding(mode, proposed)
    }

    private static func keyDisplayName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Tab: "Tab"
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Delete: "Delete"
        case kVK_ForwardDelete: "Forward Delete"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        default:
            event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
    }
}
