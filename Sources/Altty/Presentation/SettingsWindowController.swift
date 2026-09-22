import AppKit
import Carbon

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private extension ListDensity {
    var title: String {
        switch self {
        case .compact: "Compact"
        case .comfortable: "Comfortable"
        }
    }
}

struct ProductInformation: Equatable {
    let name: String
    let version: String
    let build: String

    var summary: String { "\(name) \(version) (\(build))" }

    static var current: ProductInformation {
        let info = Bundle.main.infoDictionary ?? [:]
        return ProductInformation(
            name: info["CFBundleName"] as? String ?? "Altty",
            version: info["CFBundleShortVersionString"] as? String ?? "Development",
            build: info["CFBundleVersion"] as? String ?? "local"
        )
    }
}

enum SettingsAboutAction: Equatable {
    case project
    case support
    case checkForUpdates
}

struct SettingsWindowObservedState: Equatable {
    let paneTitles: [String]
    let generalSettings: GeneralSettings
    let generalInlineMessage: String?
    let productSummary: String
    let sidebarHasKeyboardFocus: Bool
    let sidebarAccessibilityLabel: String?
    let focusedAccessibilityLabel: String?
    let showsLoginItemsRecovery: Bool
    let mouseScrollControlTitle: String
    let mouseScrollMessage: String?
    let showsInputMonitoringRecovery: Bool
}

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private struct Pane: Equatable {
        let title: String
        let symbol: String
        let detail: String

        static let general = Pane(title: "General", symbol: "gearshape", detail: "Altty remains available from the menu bar while required system access is unavailable.")
        static let shortcuts = Pane(title: "Shortcuts", symbol: "keyboard", detail: "Choose one shortcut per switcher. Hold Shift with either shortcut to navigate in reverse.")
        static let exceptions = Pane(title: "Exceptions", symbol: "list.bullet.rectangle", detail: "Hide matching windows or pass both Altty shortcuts through to a frontmost application.")
        static let about = Pane(title: "About", symbol: "info.circle", detail: "Altty is a private, title-list window switcher for macOS 15.")
        static let all = [general, shortcuts, exceptions, about]
    }

    private let onCommand: (SwitcherCommand) -> Void
    private let statusLabel = NSTextField(labelWithString: "Starting…")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "Accessibility: Checking…")
    private let accessibilityDetailLabel = NSTextField(wrappingLabelWithString: "Checking Accessibility permission.")
    private let skyLightStatusLabel = NSTextField(labelWithString: "SkyLight: Checking…")
    private let skyLightDetailLabel = NSTextField(wrappingLabelWithString: "Checking WindowServer capability.")
    private let accessibilityButton = SettingsFocusableButton(title: "Grant Accessibility…", target: nil, action: #selector(requestAccessibility))
    private let recheckButton = SettingsFocusableButton(title: "Check Readiness", target: nil, action: #selector(recheck))
    private lazy var launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Launch Altty at login",
        target: self,
        action: #selector(generalControlsChanged)
    )
    private lazy var visibleRowsPopUp: NSPopUpButton = {
        let control = NSPopUpButton()
        control.addItems(withTitles: ["6 rows", "7 rows", "8 rows"])
        control.target = self
        control.action = #selector(generalControlsChanged)
        return control
    }()
    private lazy var mouseScrollCheckbox = NSButton(
        checkboxWithTitle: "Reverse mouse wheel direction",
        target: self,
        action: #selector(generalControlsChanged)
    )
    private let mouseScrollMessageLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var inputMonitoringButton = NSButton(
        title: "Allow Input Monitoring…",
        target: self,
        action: #selector(requestMouseScrollPermission)
    )
    private lazy var densityPopUp: NSPopUpButton = {
        let control = NSPopUpButton()
        control.addItems(withTitles: ListDensity.allCases.map(\.title))
        control.target = self
        control.action = #selector(generalControlsChanged)
        return control
    }()
    private let generalMessageLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var openLoginItemsButton = NSButton(
        title: "Open Login Items Settings…",
        target: self,
        action: #selector(openLoginItemsSettings)
    )
    private let contentContainer = NSView()
    private let sidebar = NSTableView()
    private let shortcutErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let shortcutPendingLabel = NSTextField(labelWithString: "")
    private let exceptions: any ExceptionsAdapter
    private let productInformation: ProductInformation
    private var displayedGeneralSettings = GeneralSettings.defaults
    private var generalInlineMessage: String?
    private lazy var exceptionsController = ExceptionsSettingsViewController(
        applications: exceptions
    ) {
        [weak self] rules in
        self?.onCommand(.replaceExceptionRules(rules))
    }
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

    init(
        exceptions: any ExceptionsAdapter,
        productInformation: ProductInformation = .current,
        onCommand: @escaping (SwitcherCommand) -> Void
    ) {
        self.exceptions = exceptions
        self.productInformation = productInformation
        self.onCommand = onCommand
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Altty Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 600)
        window.autorecalculatesKeyViewLoop = false
        super.init(window: window)
        accessibilityButton.target = self
        recheckButton.target = self
        accessibilityButton.setAccessibilityLabel("Grant Accessibility Permission")
        recheckButton.setAccessibilityLabel("Check Altty readiness")
        launchAtLoginCheckbox.setAccessibilityLabel("Launch Altty at login")
        mouseScrollCheckbox.setAccessibilityLabel("Reverse mouse wheel direction")
        mouseScrollCheckbox.setAccessibilityHelp("Reverse mouse scrolling while keeping trackpad scrolling unchanged.")
        inputMonitoringButton.setAccessibilityLabel("Allow Altty Input Monitoring")
        inputMonitoringButton.isHidden = true
        mouseScrollMessageLabel.isHidden = true
        visibleRowsPopUp.setAccessibilityLabel("Visible switcher rows")
        densityPopUp.setAccessibilityLabel("Switcher row spacing")
        openLoginItemsButton.setAccessibilityLabel("Open Login Items Settings")
        configureSidebar(on: window)
        showPane(.general)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var observedState: SettingsWindowObservedState {
        SettingsWindowObservedState(
            paneTitles: Pane.all.map(\.title),
            generalSettings: displayedGeneralSettings,
            generalInlineMessage: generalInlineMessage,
            productSummary: productInformation.summary,
            sidebarHasKeyboardFocus: window?.firstResponder === sidebar,
            sidebarAccessibilityLabel: sidebar.accessibilityLabel(),
            focusedAccessibilityLabel: (window?.firstResponder as? NSView)?
                .accessibilityLabel(),
            showsLoginItemsRecovery: !openLoginItemsButton.isHidden,
            mouseScrollControlTitle: mouseScrollCheckbox.title,
            mouseScrollMessage: mouseScrollMessageLabel.isHidden ? nil : mouseScrollMessageLabel.stringValue,
            showsInputMonitoringRecovery: !inputMonitoringButton.isHidden
        )
    }

    func show(state: SwitcherPresentationState) {
        update(state: state)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(sidebar)
    }

    func update(state: SwitcherPresentationState) {
        statusLabel.stringValue = state.readinessTitle
        accessibilityStatusLabel.stringValue = state.accessibilityStatusTitle
        accessibilityDetailLabel.stringValue = state.accessibilityDetail
        skyLightStatusLabel.stringValue = state.skyLightStatusTitle
        skyLightDetailLabel.stringValue = state.skyLightDetail
        accessibilityButton.isHidden = !state.showsAccessibilityAction
        updateGeneral(state.generalSettings)
        let scrollMessage = state.generalSettings.mouseScrollMessage(accessibility: state.accessibility)
        mouseScrollMessageLabel.stringValue = scrollMessage ?? ""
        mouseScrollMessageLabel.isHidden = scrollMessage == nil
        inputMonitoringButton.isHidden = !state.generalSettings.current.reverseMouseWheel
            || (state.generalSettings.mouseScrollStatus != .inputMonitoringRequired
                && state.generalSettings.mouseScrollStatus != .unavailable)
        updateShortcuts(state.shortcutSettings)
        exceptionsController.update(state.exceptionSettings)
    }

    private func configureSidebar(on window: NSWindow) {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        sidebar.addTableColumn(NSTableColumn(identifier: .init("Pane")))
        sidebar.headerView = nil
        sidebar.rowHeight = 32
        sidebar.style = .sourceList
        sidebar.allowsEmptySelection = false
        sidebar.setAccessibilityLabel("Settings sections")
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
        let icon = NSImageView(image: NSImage(
            systemSymbolName: pane.symbol,
            accessibilityDescription: pane.title
        ) ?? NSImage())
        let label = NSTextField(labelWithString: pane.title)
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.textField = label
        cell.imageView = icon
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard sidebar.selectedRow >= 0 else { return }
        showPane(Pane.all[sidebar.selectedRow])
    }

    private func showPane(_ pane: Pane) {
        let root = SettingsDocumentView()
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
            stack.addArrangedSubview(separator())
            stack.addArrangedSubview(launchAtLoginCheckbox)
            stack.addArrangedSubview(mouseScrollCheckbox)
            let mouseScrollDetail = NSTextField(wrappingLabelWithString:
                "Reverse mouse scrolling. Trackpad direction stays as set in macOS.")
            mouseScrollDetail.textColor = .secondaryLabelColor
            mouseScrollDetail.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(mouseScrollDetail)
            mouseScrollMessageLabel.textColor = .systemOrange
            mouseScrollMessageLabel.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(mouseScrollMessageLabel)
            stack.addArrangedSubview(inputMonitoringButton)
            stack.addArrangedSubview(formRow(label: "Visible rows", control: visibleRowsPopUp))
            stack.addArrangedSubview(formRow(label: "Row spacing", control: densityPopUp))
            generalMessageLabel.textColor = .systemOrange
            generalMessageLabel.font = .systemFont(ofSize: 12)
            generalMessageLabel.maximumNumberOfLines = 4
            stack.addArrangedSubview(generalMessageLabel)
            stack.addArrangedSubview(openLoginItemsButton)
            configureGeneralKeyViewLoop()
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
        } else if pane == .exceptions {
            stack.addArrangedSubview(exceptionsController.view)
        } else if pane == .about {
            let product = NSTextField(labelWithString: productInformation.summary)
            product.font = .systemFont(ofSize: 16, weight: .semibold)
            let copyright = NSTextField(
                wrappingLabelWithString: "A fast, window-first switcher for macOS."
            )
            copyright.textColor = .secondaryLabelColor
            let project = NSButton(
                title: "Project Website",
                target: self,
                action: #selector(openProject)
            )
            let support = NSButton(
                title: "Support and Issues",
                target: self,
                action: #selector(openSupport)
            )
            let update = NSButton(
                title: "Check for Updates…",
                target: self,
                action: #selector(checkForUpdates)
            )
            project.setAccessibilityLabel("Open Altty project website")
            support.setAccessibilityLabel("Open Altty support and issues")
            update.setAccessibilityLabel("Check for Altty updates")
            stack.addArrangedSubview(product)
            stack.addArrangedSubview(copyright)
            stack.addArrangedSubview(NSStackView(views: [project, support, update]))
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
        if pane == .general {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.documentView = root
            contentContainer.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                root.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            ])
            return
        }
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
    @objc private func requestMouseScrollPermission() { onCommand(.requestMouseScrollPermission) }
    @objc private func openProject() { performAboutAction(.project) }
    @objc private func openSupport() { performAboutAction(.support) }
    @objc private func checkForUpdates() { performAboutAction(.checkForUpdates) }
    @objc private func openLoginItemsSettings() { onCommand(.openLoginItemsSettings) }

    func advanceKeyboardFocus() {
        if window?.firstResponder === sidebar {
            window?.makeFirstResponder(accessibilityButton)
        } else {
            window?.selectNextKeyView(window?.firstResponder)
        }
    }

    func performAboutAction(_ action: SettingsAboutAction) {
        switch action {
        case .project: onCommand(.openExternalPage(.project))
        case .support: onCommand(.openExternalPage(.support))
        case .checkForUpdates: onCommand(.checkForUpdates)
        }
    }

    func replaceGeneralSettings(_ settings: GeneralSettings) {
        onCommand(.replaceGeneralSettings(settings))
    }

    func toggleMouseScrollReversal() { mouseScrollCheckbox.performClick(nil) }

    @objc private func generalControlsChanged() {
        guard (0..<3).contains(visibleRowsPopUp.indexOfSelectedItem),
              ListDensity.allCases.indices.contains(densityPopUp.indexOfSelectedItem) else {
            return
        }
        replaceGeneralSettings(GeneralSettings(
            launchAtLogin: launchAtLoginCheckbox.state == .on,
            listPresentation: ListPresentationPreferences(
                visibleRowCount: visibleRowsPopUp.indexOfSelectedItem + 6,
                density: ListDensity.allCases[densityPopUp.indexOfSelectedItem]
            ),
            reverseMouseWheel: mouseScrollCheckbox.state == .on
        ))
    }

    private func updateGeneral(_ state: GeneralSettingsState) {
        displayedGeneralSettings = state.displayed
        generalInlineMessage = state.inlineMessage
        launchAtLoginCheckbox.state = state.displayed.launchAtLogin ? .on : .off
        mouseScrollCheckbox.state = state.displayed.reverseMouseWheel ? .on : .off
        visibleRowsPopUp.selectItem(at: state.displayed.listPresentation.visibleRowCount - 6)
        densityPopUp.selectItem(at: ListDensity.allCases.firstIndex(
            of: state.displayed.listPresentation.density
        ) ?? 0)
        generalMessageLabel.stringValue = state.inlineMessage ?? ""
        generalMessageLabel.isHidden = state.inlineMessage == nil
        openLoginItemsButton.isHidden = !state.launchAtLoginRequiresApproval
    }

    private func configureGeneralKeyViewLoop() {
        sidebar.nextKeyView = accessibilityButton
        accessibilityButton.nextKeyView = recheckButton
        recheckButton.nextKeyView = launchAtLoginCheckbox
        launchAtLoginCheckbox.nextKeyView = mouseScrollCheckbox
        mouseScrollCheckbox.nextKeyView = inputMonitoringButton
        inputMonitoringButton.nextKeyView = visibleRowsPopUp
        visibleRowsPopUp.nextKeyView = densityPopUp
        densityPopUp.nextKeyView = openLoginItemsButton
        openLoginItemsButton.nextKeyView = sidebar
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: 430).isActive = true
        return separator
    }

    private func formRow(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

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

private final class SettingsFocusableButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
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
