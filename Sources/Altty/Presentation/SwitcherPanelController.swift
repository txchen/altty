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

struct SwitcherListLayout {
    let size: ListSize
    let visibleRowCapacity: Int
    let height: CGFloat

    init(rowCount: Int, preference: ListSize, screenHeight: CGFloat, visibleHeight: CGFloat) {
        let maximumHeight = max(0, min(screenHeight * 0.8, visibleHeight))
        let candidates: [ListSize] = preference == .auto ? [.large, .medium, .small] : [preference]
        size = candidates.first { 50 + CGFloat(max(rowCount, 1)) * ($0.rowHeight + 2) <= maximumHeight }
            ?? candidates.last!
        let stride = CGFloat(size.rowHeight + 2)
        visibleRowCapacity = max(1, Int(max(0, maximumHeight - 50) / stride))
        height = min(maximumHeight, 50 + CGFloat(min(max(rowCount, 1), visibleRowCapacity)) * stride)
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
    private var resolvedSize: ListSize = .large
    private var visibleRowCapacity = 0

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
            visibleRowCapacity: visibleRowCapacity,
            selectedRowIsVisible: selectedRowIsVisible
        )
    }

    init(
        displayProvider: any SwitcherDisplayProviding = SystemSwitcherDisplayProvider(),
        panel: NSPanel? = nil
    ) {
        self.displayProvider = displayProvider
        self.panel = panel ?? NSPanel(
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
        // Resolve the final viewport while still off-screen. Ordering the panel
        // first can expose its material before NSTableView creates any rows.
        panel.contentView?.layoutSubtreeIfNeeded()
        if tableView.selectedRow >= 0 {
            tableView.scrollRowToVisible(tableView.selectedRow)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.display()
        panel.orderFrontRegardless()
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
        let oldSize = resolvedSize
        let preferencesChanged = previous?.listPresentation != state.listPresentation
        if structureChanged || preferencesChanged {
            resizeForRows(state.rows.count, preferences: state.listPresentation)
        }
        let layoutChanged = preferencesChanged || resolvedSize != oldSize
        tableView.rowHeight = CGFloat(resolvedSize.rowHeight)
        if structureChanged || layoutChanged {
            tableView.reloadData()
        } else if let previous {
            let changed = IndexSet(state.rows.indices.filter { previous.rows[$0] != state.rows[$0] })
            if !changed.isEmpty { tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0)) }
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
        // Own the geometry: AppKit's automatic/inset style adds implicit vertical
        // padding, making the last row scroll even when every row should fit.
        tableView.style = .plain
        tableView.usesAutomaticRowHeights = false
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
        scrollView.hasVerticalScroller = false
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
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
            header.widthAnchor.constraint(equalTo: content.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -16),
            header.heightAnchor.constraint(equalToConstant: 40),
        ])
        panel.contentView = background
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SwitcherSelectionRowView()
    }

    private func makeRow(for rowState: SwitcherPanelRow) -> NSView {
        let iconSize: CGFloat = switch resolvedSize {
        case .small: 32
        case .medium: 36
        case .large, .auto: 40
        }
        let titleSize: CGFloat = switch resolvedSize {
        case .small: 13
        case .medium: 14
        case .large, .auto: 16
        }
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
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
        ])

        let title = NSTextField(labelWithString: rowState.title)
        title.font = .systemFont(ofSize: titleSize, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        let subtitle = NSTextField(labelWithString: rowState.applicationName)
        subtitle.font = .systemFont(ofSize: resolvedSize == .small ? 11 : 12)
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
        return scrollView.documentVisibleRect.contains(
            tableView.rect(ofRow: tableView.selectedRow)
        )
    }

    private func resizeForRows(_ rowCount: Int, preferences: ListPresentationPreferences) {
        let display = state.flatMap(preferredDisplay(for:))
        let layout = SwitcherListLayout(rowCount: rowCount, preference: preferences.size,
            screenHeight: display?.frame.height ?? 800,
            visibleHeight: display?.visibleFrame.height ?? 800)
        resolvedSize = layout.size
        visibleRowCapacity = layout.visibleRowCapacity
        panel.setContentSize(NSSize(width: 520, height: layout.height))
    }

    private func preferredDisplay(for state: SwitcherPanelState) -> SwitcherDisplay? {
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
        return displays.first { $0.frame.contains(displayProvider.pointerLocation) }
            ?? invokingDisplay
            ?? displays.first(where: \.isPrimary)
            ?? displays.first
    }

    private func placePanel(state: SwitcherPanelState) {
        guard let display = preferredDisplay(for: state) else { return }
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

/// Keep text in its normal appearance over a translucent accent fill.
final class SwitcherSelectionRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
        NSColor.controlAccentColor.withAlphaComponent(highContrast ? 0.3 : 0.2).setFill()
        outline.fill()
        NSColor.controlAccentColor.setStroke()
        outline.lineWidth = highContrast ? 2 : 1.5
        outline.stroke()
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
