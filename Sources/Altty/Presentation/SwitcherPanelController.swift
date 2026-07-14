import AppKit

struct SwitcherPanelObservedState: Equatable {
    let isVisible: Bool
    let title: String?
    let shortcut: String?
    let rowCount: Int
    let selectedIdentity: WindowIdentity?
    let rows: [SwitcherPanelObservedRow]
}

struct SwitcherPanelObservedRow: Equatable {
    let identity: WindowIdentity
    let title: String
    let applicationName: String
    let badges: [String]
    let showsApplicationIcon: Bool
}

@MainActor
final class SwitcherPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var onInteraction: ((SwitcherSessionEvent) -> Void)?

    private var state: SwitcherPanelState?
    private let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    let tableView = SwitcherTableView()
    private let scrollView = NSScrollView()

    var observedState: SwitcherPanelObservedState {
        SwitcherPanelObservedState(
            isVisible: panel.isVisible,
            title: state?.title,
            shortcut: state?.shortcutDescription,
            rowCount: tableView.numberOfRows,
            selectedIdentity: state?.rows[safe: tableView.selectedRow]?.identity,
            rows: (0..<tableView.numberOfRows).compactMap { row in
                (tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
                    as? SwitcherRowView)?.observedRow
            }
        )
    }

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    func show(state: SwitcherPanelState) {
        update(state: state)
        centerOnPointerDisplay()
        panel.orderFrontRegardless()
    }

    func update(state: SwitcherPanelState) {
        self.state = state
        titleLabel.stringValue = state.title
        shortcutLabel.stringValue = state.shortcutDescription
        tableView.reloadData()
        if let selectedRow = state.rows.firstIndex(where: {
            $0.identity == state.selectedIdentity
        }) {
            tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedRow)
        }
        resizeForRows(state.rows.count)
    }

    func dismiss() {
        panel.orderOut(nil)
        state = nil
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { state?.rows.count ?? 0 }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let row = state?.rows[row] else { return nil }
        return makeRow(for: row)
    }

    private func configurePanel() {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        let header = NSStackView(views: [titleLabel, NSView(), shortcutLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 8, right: 14)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        shortcutLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        shortcutLabel.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SwitcherWindow"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.setAccessibilityLabel("Switcher windows")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onHover = { [weak self] row in self?.hover(row: row) }
        tableView.onClick = { [weak self] row in self?.click(row: row) }
        tableView.onScroll = { [weak self] direction in self?.scroll(direction: direction) }

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let content = NSStackView(views: [header, scrollView])
        content.orientation = .vertical
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: 40),
        ])
        panel.contentView = background
    }

    private func makeRow(for rowState: SwitcherPanelRow) -> NSView {
        let applicationIcon = rowState.applicationBundlePath.map {
            NSWorkspace.shared.icon(forFile: $0)
        }
        let icon = NSImageView(image: applicationIcon ?? NSImage(
            systemSymbolName: "app.fill",
            accessibilityDescription: "Application"
        ) ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
        ])

        let title = NSTextField(labelWithString: rowState.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        let subtitle = NSTextField(labelWithString: rowState.applicationName)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let badges = stateBadges(for: rowState)
        let badgeLabel = NSTextField(labelWithString: badges.joined(separator: "  "))
        badgeLabel.font = .systemFont(ofSize: 10, weight: .medium)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.setAccessibilityLabel(badges.joined(separator: ", "))

        let row = SwitcherRowView(
            views: [icon, labels, NSView(), badgeLabel],
            observedRow: observedRow(for: rowState)
        )
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.row)
        row.setAccessibilityLabel("\(rowState.title), \(rowState.applicationName)")
        return row
    }

    private func stateBadges(for row: SwitcherPanelRow) -> [String] {
        var badges: [String] = []
        if row.isMinimized { badges.append("Minimized") }
        if row.applicationIsHidden { badges.append("Hidden") }
        if row.isFullscreen { badges.append("Full Screen") }
        return badges
    }

    func hover(row: Int) {
        guard let row = state?.rows[safe: row] else { return }
        onInteraction?(.select(row.identity))
    }

    func click(row: Int) {
        guard let row = state?.rows[safe: row] else { return }
        onInteraction?(.confirm(row.identity))
    }

    func scroll(direction: SwitchDirection) {
        onInteraction?(.navigate(direction))
    }

    private func observedRow(for row: SwitcherPanelRow) -> SwitcherPanelObservedRow {
        SwitcherPanelObservedRow(
            identity: row.identity,
            title: row.title,
            applicationName: row.applicationName,
            badges: stateBadges(for: row),
            showsApplicationIcon: true
        )
    }

    private func resizeForRows(_ rowCount: Int) {
        let visibleRows = min(max(rowCount, 1), 8)
        panel.setContentSize(NSSize(width: 520, height: 40 + visibleRows * 56))
    }

    private func centerOnPointerDisplay() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.midY - panel.frame.height / 2
        ))
    }
}

final class SwitcherRowView: NSView {
    let observedRow: SwitcherPanelObservedRow

    init(views: [NSView], observedRow: SwitcherPanelObservedRow) {
        self.observedRow = observedRow
        super.init(frame: .zero)
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class SwitcherTableView: NSTableView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onScroll: ((SwitchDirection) -> Void)?
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseMoved(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { onHover?(row) }
    }

    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { onClick?(row) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
              event.scrollingDeltaY != 0 else { return }
        onScroll?(event.scrollingDeltaY > 0 ? .backward : .forward)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
