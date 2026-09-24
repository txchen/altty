import AppKit
import UniformTypeIdentifiers

@MainActor
final class ExceptionsSettingsViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate {
    typealias RuleEditor = (
        _ initial: ExceptionRule?,
        _ bundleIdentifier: String,
        _ matchType: ExceptionMatchType
    ) -> ExceptionRule?

    private let onRulesChanged: ([ExceptionRule]) -> Void
    private let applications: any ExceptionsAdapter
    private let ruleEditor: RuleEditor?
    private let table = NSTableView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let pendingLabel = NSTextField(labelWithString: "")
    private var rules: [ExceptionRule] = []
    private lazy var addButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.addItems(withTitles: [
            "Add Exception…",
            "From Running Application…",
            "Choose Application Bundle…",
            "Enter Bundle Identifier…",
        ])
        button.target = self
        button.action = #selector(addException(_:))
        return button
    }()
    private lazy var editButton = NSButton(
        title: "Edit…",
        target: self,
        action: #selector(editException)
    )
    private lazy var deleteButton = NSButton(
        title: "Delete",
        target: self,
        action: #selector(deleteException)
    )
    private lazy var moveUpButton = NSButton(
        title: "Move Up",
        target: self,
        action: #selector(moveExceptionUp)
    )
    private lazy var moveDownButton = NSButton(
        title: "Move Down",
        target: self,
        action: #selector(moveExceptionDown)
    )

    init(
        applications: any ExceptionsAdapter,
        ruleEditor: RuleEditor? = nil,
        onRulesChanged: @escaping ([ExceptionRule]) -> Void
    ) {
        self.applications = applications
        self.ruleEditor = ruleEditor
        self.onRulesChanged = onRulesChanged
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        configureTable()
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 250).isActive = true

        let buttons = NSStackView(views: [
            addButton, editButton, deleteButton, moveUpButton, moveDownButton,
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        pendingLabel.textColor = .secondaryLabelColor
        pendingLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.maximumNumberOfLines = 3

        let stack = NSStackView(views: [scroll, buttons, pendingLabel, errorLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        self.view = stack
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        updateButtons()
    }

    func update(_ state: ExceptionSettingsState) {
        loadViewIfNeeded()
        let selectedIdentity = table.selectedRow >= 0
            ? rules[table.selectedRow].identity
            : nil
        rules = state.displayedRules
        table.reloadData()
        if let selectedIdentity,
           let index = rules.firstIndex(where: { $0.identity == selectedIdentity }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        pendingLabel.stringValue = state.pending == nil
            ? ""
            : "This change will take effect after the current switcher session ends."
        pendingLabel.isHidden = state.pending == nil
        errorLabel.stringValue = state.inlineMessage ?? ""
        errorLabel.isHidden = state.inlineMessage == nil
        updateButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        ruleRow(rules[row])
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    private func configureTable() {
        table.addTableColumn(NSTableColumn(identifier: .init("Exception")))
        table.headerView = nil
        table.rowHeight = 54
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
    }

    private func ruleRow(_ rule: ExceptionRule) -> NSView {
        let cell = NSTableCellView()
        let resolved = applications.exceptionApplication(
            bundleIdentifier: rule.bundleIdentifier
        )
        let image = resolved?.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: "Application")
            ?? NSImage()
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: resolved?.name ?? "Missing Application")
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        let identifier = NSTextField(labelWithString: rule.bundleIdentifier)
        identifier.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        identifier.textColor = .secondaryLabelColor
        identifier.lineBreakMode = .byTruncatingMiddle
        let identity = NSStackView(views: [name, identifier])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 2

        let match = NSTextField(labelWithString: rule.matchType.title)
        match.alignment = .right
        match.font = .systemFont(ofSize: 11, weight: .medium)
        let summary = NSTextField(labelWithString: rule.summary)
        summary.alignment = .right
        summary.font = .systemFont(ofSize: 10)
        summary.textColor = .secondaryLabelColor
        let policy = NSStackView(views: [match, summary])
        policy.orientation = .vertical
        policy.alignment = .trailing
        policy.spacing = 2

        let row = NSStackView(views: [imageView, identity, policy])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            identity.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            row.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func updateButtons() {
        let row = table.selectedRow
        let hasSelection = rules.indices.contains(row)
        editButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        moveUpButton.isEnabled = hasSelection && row > 0
        moveDownButton.isEnabled = hasSelection && row < rules.count - 1
    }

    @objc func addException(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        sender.selectItem(at: 0)
        switch selectedIndex {
        case 1:
            addFromRunningApplication()
        case 2:
            addFromApplicationBundle()
        case 3:
            if let rule = promptForRule() { submitNew(rule) }
        default:
            break
        }
    }

    private func addFromRunningApplication() {
        var available: [String: ExceptionApplication] = [:]
        for application in applications.runningExceptionApplications() {
            available[application.bundleIdentifier] = application
        }
        let choices = available.values.sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                return comparison == .orderedSame
                    ? $0.bundleIdentifier < $1.bundleIdentifier
                    : comparison == .orderedAscending
            }
        guard !choices.isEmpty else {
            showAlert("No applications with bundle identifiers are running.")
            return
        }
        let picker = NSPopUpButton()
        picker.addItems(withTitles: choices.map { "\($0.name) — \($0.bundleIdentifier)" })
        picker.frame.size.width = 380
        let alert = NSAlert()
        alert.messageText = "Choose a Running Application"
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = picker
        guard alert.runModal() == .alertFirstButtonReturn,
              choices.indices.contains(picker.indexOfSelectedItem) else { return }
        editExistingOrCreate(
            bundleIdentifier: choices[picker.indexOfSelectedItem].bundleIdentifier,
            matchType: .exact
        )
    }

    private func addFromApplicationBundle() {
        let picker = NSOpenPanel()
        picker.title = "Choose an Application"
        picker.prompt = "Choose"
        picker.allowedContentTypes = [.applicationBundle]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK,
              let url = picker.url,
              let application = applications.exceptionApplication(at: url) else {
            if picker.url != nil {
                showAlert("The selected application has no bundle identifier.")
            }
            return
        }
        editExistingOrCreate(
            bundleIdentifier: application.bundleIdentifier,
            matchType: .exact
        )
    }

    @objc private func editException() {
        let row = table.selectedRow
        guard rules.indices.contains(row) else { return }
        let original = rules[row]
        guard let updated = promptForRule(initial: original) else { return }
        submit(updated, replacing: original.identity)
    }

    @objc private func deleteException() {
        let row = table.selectedRow
        guard rules.indices.contains(row) else { return }
        var updated = rules
        updated.remove(at: row)
        onRulesChanged(updated)
    }

    @objc private func moveExceptionUp() { moveSelectedRule(by: -1) }
    @objc private func moveExceptionDown() { moveSelectedRule(by: 1) }

    private func moveSelectedRule(by offset: Int) {
        let source = table.selectedRow
        let destination = source + offset
        guard rules.indices.contains(source), rules.indices.contains(destination) else { return }
        var updated = rules
        updated.swapAt(source, destination)
        onRulesChanged(updated)
    }

    private func submit(
        _ rule: ExceptionRule,
        replacing originalIdentity: ExceptionRuleIdentity? = nil
    ) {
        onRulesChanged(ExceptionRule.replacingDuplicateIdentity(
            in: rules,
            with: rule,
            replacing: originalIdentity
        ))
    }

    private func submitNew(_ proposed: ExceptionRule) {
        if let existing = rules.first(where: { $0.identity == proposed.identity }) {
            guard let updated = promptForRule(initial: existing) else { return }
            submit(updated, replacing: existing.identity)
        } else {
            submit(proposed)
        }
    }

    private func editExistingOrCreate(
        bundleIdentifier: String,
        matchType: ExceptionMatchType
    ) {
        let identity = ExceptionRuleIdentity(
            bundleIdentifier: bundleIdentifier,
            matchType: matchType
        )
        if let existing = rules.first(where: { $0.identity == identity }) {
            guard let updated = promptForRule(initial: existing) else { return }
            submit(updated, replacing: existing.identity)
        } else if let rule = promptForRule(
            bundleIdentifier: bundleIdentifier,
            matchType: matchType
        ) {
            submit(rule)
        }
    }

    private func promptForRule(
        initial: ExceptionRule? = nil,
        bundleIdentifier: String = "",
        matchType: ExceptionMatchType = .exact
    ) -> ExceptionRule? {
        if let ruleEditor {
            return ruleEditor(initial, bundleIdentifier, matchType)
        }
        let identifier = NSTextField(string: initial?.bundleIdentifier ?? bundleIdentifier)
        identifier.placeholderString = "com.example.Application"
        let match = NSPopUpButton()
        match.addItems(withTitles: ExceptionMatchType.allCases.map(\.title))
        match.selectItem(at: ExceptionMatchType.allCases.firstIndex(
            of: initial?.matchType ?? matchType
        ) ?? 0)
        let hide = NSButton(
            checkboxWithTitle: "Hide matching windows",
            target: nil,
            action: nil
        )
        hide.state = (initial?.hide ?? true) ? .on : .off
        let ignore = NSPopUpButton()
        ignore.addItems(withTitles: ExceptionIgnore.allCases.map(\.title))
        ignore.selectItem(at: ExceptionIgnore.allCases.firstIndex(
            of: initial?.ignore ?? .none
        ) ?? 0)

        let stack = NSStackView(views: [
            formRow(label: "Bundle ID", control: identifier),
            formRow(label: "Match", control: match),
            hide,
            formRow(label: "Ignore", control: ignore),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: 130)
        identifier.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let alert = NSAlert()
        alert.messageText = initial == nil ? "Add Exception" : "Edit Exception"
        alert.informativeText = "Exact rules match one bundle ID. Prefix rules match a controlled application family."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = stack
        while alert.runModal() == .alertFirstButtonReturn {
            guard ExceptionMatchType.allCases.indices.contains(match.indexOfSelectedItem),
                  ExceptionIgnore.allCases.indices.contains(ignore.indexOfSelectedItem),
                  let rule = ExceptionRule(
                    bundleIdentifier: identifier.stringValue,
                    matchType: ExceptionMatchType.allCases[match.indexOfSelectedItem],
                    hide: hide.state == .on,
                    ignore: ExceptionIgnore.allCases[ignore.indexOfSelectedItem]
                  ) else {
                NSSound.beep()
                alert.informativeText = "Bundle identifier must not be empty."
                continue
            }
            return rule
        }
        return nil
    }

    private func formRow(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 78).isActive = true
        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Unable to Add Exception"
        alert.informativeText = message
        alert.runModal()
    }
}
