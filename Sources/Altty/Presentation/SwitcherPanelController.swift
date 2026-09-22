import AppKit

struct SwitcherPanelObservedState: Equatable {
    let isVisible: Bool
    let title: String?
    let shortcut: String?
    let rowCount: Int
    let selectedIdentity: WindowIdentity?
    let rows: [SwitcherPanelObservedRow]
    var displayIdentifier: String? = nil
    var panelFrame: CGRect = .zero
    var visibleRowCapacity: Int = 0
    var selectedRowIsVisible: Bool = false
}

struct SwitcherPanelObservedRow: Equatable {
    let identity: WindowIdentity
    let title: String
    let applicationName: String
    let badges: [String]
    let showsApplicationIcon: Bool
    var usesSingleLineText: Bool = true
    var accessibilityLabel: String = ""
    var accessibilityRole: String = ""
}

struct SwitcherDisplay: Equatable {
    let identifier: String
    let frame: CGRect
    let visibleFrame: CGRect
    let windowServerFrame: CGRect
    let isPrimary: Bool
}

@MainActor
protocol SwitcherDisplayProviding: AnyObject {
    var pointerLocation: CGPoint { get }
    var displays: [SwitcherDisplay] { get }
    func frame(of window: WindowIdentity) -> CGRect?
}

@MainActor
final class SystemSwitcherDisplayProvider: SwitcherDisplayProviding {
    var pointerLocation: CGPoint { NSEvent.mouseLocation }

    var displays: [SwitcherDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return SwitcherDisplay(
                identifier: String(displayID),
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                windowServerFrame: CGDisplayBounds(displayID),
                isPrimary: displayID == CGMainDisplayID()
            )
        }
    }

    func frame(of window: WindowIdentity) -> CGRect? {
        guard let entries = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(window.wid)
        ) as? [[String: Any]],
        let bounds = entries.first?[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: bounds)
    }
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
    private let displayProvider: any SwitcherDisplayProviding
    private var displayIdentifier: String?

    var observedState: SwitcherPanelObservedState {
        SwitcherPanelObservedState(
            isVisible: panel.isVisible,
            title: state?.title,
            shortcut: state?.shortcutDescription,
            rowCount: tableView.numberOfRows,
            selectedIdentity: state?.rows[safe: tableView.selectedRow]?.identity,
            rows: (0..<tableView.numberOfRows).compactMap { row in
                guard let view = tableView.view(
                    atColumn: 0,
                    row: row,
                    makeIfNecessary: true
                ) as? SwitcherRowView else { return nil }
                var observed = view.observedRow
                observed.accessibilityLabel = view.accessibilityLabel() ?? ""
                observed.accessibilityRole = view.accessibilityRole()?.rawValue ?? ""
                return observed
            },
            displayIdentifier: displayIdentifier,
            panelFrame: panel.frame,
            visibleRowCapacity: state?.listPresentation.visibleRowCount ?? 0,
            selectedRowIsVisible: selectedRowIsVisible
        )
    }

    init(displayProvider: any SwitcherDisplayProviding = SystemSwitcherDisplayProvider()) {
        self.displayProvider = displayProvider
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
        placePanel(state: state)
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        if tableView.selectedRow >= 0 {
            tableView.scrollRowToVisible(tableView.selectedRow)
        }
    }

    func update(state: SwitcherPanelState) {
        let previous = self.state
        guard previous != state else { return }
        self.state = state
        if previous?.title != state.title { titleLabel.stringValue = state.title }
        if previous?.shortcutDescription != state.shortcutDescription {
            shortcutLabel.stringValue = state.shortcutDescription
        }
        let structureChanged = previous?.rows.map(\.identity) != state.rows.map(\.identity)
        let layoutChanged = previous?.listPresentation != state.listPresentation
        if layoutChanged { tableView.rowHeight = rowHeight(for: state.listPresentation.density) }
        if structureChanged {
            tableView.reloadData()
        } else if let previous {
            let changed = IndexSet(state.rows.indices.filter { previous.rows[$0] != state.rows[$0] })
            if !changed.isEmpty { tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0)) }
        }
        if structureChanged || layoutChanged {
            resizeForRows(state.rows.count, preferences: state.listPresentation)
        }
        if let selectedRow = state.rows.firstIndex(where: { $0.identity == state.selectedIdentity }) {
            if tableView.selectedRow != selectedRow {
                tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
            }
            if structureChanged || layoutChanged || previous?.selectedIdentity != state.selectedIdentity {
                tableView.scrollRowToVisible(selectedRow)
            }
        } else {
            tableView.deselectAll(nil)
        }
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
        labels.setHuggingPriority(.defaultLow, for: .horizontal)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let badges = stateBadges(for: rowState)
        let badgeLabel = NSTextField(labelWithString: badges.joined(separator: "  "))
        badgeLabel.font = .systemFont(ofSize: 10, weight: .medium)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.setAccessibilityLabel(badges.joined(separator: ", "))
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let accessibleBadges = badges.isEmpty ? "" : ", \(badges.joined(separator: ", "))"
        let accessibilityLabel = "\(rowState.title), \(rowState.applicationName)\(accessibleBadges)"
        let row = SwitcherRowView(
            views: [icon, labels, NSView(), badgeLabel],
            observedRow: SwitcherPanelObservedRow(
                identity: rowState.identity,
                title: rowState.title,
                applicationName: rowState.applicationName,
                badges: badges,
                showsApplicationIcon: icon.image != nil,
                usesSingleLineText: title.maximumNumberOfLines == 1
                    && subtitle.maximumNumberOfLines == 1,
                accessibilityLabel: accessibilityLabel,
                accessibilityRole: NSAccessibility.Role.row.rawValue
            )
        )
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.row)
        row.setAccessibilityLabel(accessibilityLabel)
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

    private var selectedRowIsVisible: Bool {
        guard tableView.selectedRow >= 0 else { return false }
        return tableView.rect(ofRow: tableView.selectedRow).intersects(
            scrollView.documentVisibleRect
        )
    }

    private func rowHeight(for density: ListDensity) -> CGFloat {
        density == .compact ? 52 : 60
    }

    private func resizeForRows(
        _ rowCount: Int,
        preferences: ListPresentationPreferences
    ) {
        let visibleRows = min(max(rowCount, 1), preferences.visibleRowCount)
        let rowHeight = rowHeight(for: preferences.density)
        panel.setContentSize(NSSize(
            width: 520,
            height: 40 + CGFloat(visibleRows) * (rowHeight + 2)
        ))
    }

    private func placePanel(state: SwitcherPanelState) {
        let displays = displayProvider.displays
        let invokingDisplay = state.invokingWindowIdentity
            .flatMap(displayProvider.frame(of:))
            .flatMap { windowFrame in
                displays
                    .map { display in
                        (
                            display: display,
                            overlap: display.windowServerFrame.intersection(windowFrame).area
                        )
                    }
                    .filter { $0.overlap > 0 }
                    .max { $0.overlap < $1.overlap }?
                    .display
            }
        let display = displays.first { $0.frame.contains(displayProvider.pointerLocation) }
            ?? invokingDisplay
            ?? displays.first(where: \.isPrimary)
            ?? displays.first
        guard let display else { return }
        let visibleFrame = display.visibleFrame
        let size = CGSize(
            width: min(panel.frame.width, visibleFrame.width),
            height: min(panel.frame.height, visibleFrame.height)
        )
        panel.setFrame(CGRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        ), display: false)
        displayIdentifier = display.identifier
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(width, 0) * max(height, 0)
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
