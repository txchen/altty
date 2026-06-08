import AppKit

final class SettingsWindowController: NSWindowController {
    private let permissionStatusLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 230),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Altty Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refreshPermissionStatus()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeContentView() -> NSView {
        let root = NSView()

        let title = NSTextField(labelWithString: "Altty")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString: "Title-list window switching with no screen recording permission.")
        subtitle.textColor = .secondaryLabelColor

        let hotkeyLabel = NSTextField(labelWithString: "Shortcut: Option + Tab")
        hotkeyLabel.font = .systemFont(ofSize: 13, weight: .medium)

        permissionStatusLabel.font = .systemFont(ofSize: 13)

        let requestButton = NSButton(title: "Grant Accessibility Permission", target: self, action: #selector(requestAccessibility))
        requestButton.bezelStyle = .rounded

        let openSettingsButton = NSButton(title: "Open System Settings", target: self, action: #selector(openSystemSettings))
        openSettingsButton.bezelStyle = .rounded

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshPermissionStatusAction))
        refreshButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [requestButton, openSettingsButton, refreshButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        let stack = NSStackView(views: [title, subtitle, hotkeyLabel, permissionStatusLabel, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
        ])
        return root
    }

    @objc private func requestAccessibility() {
        AccessibilityPermission.request()
        refreshPermissionStatus()
    }

    @objc private func openSystemSettings() {
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func refreshPermissionStatusAction() {
        refreshPermissionStatus()
    }

    private func refreshPermissionStatus() {
        if AccessibilityPermission.isTrusted {
            permissionStatusLabel.stringValue = "Accessibility: Granted"
            permissionStatusLabel.textColor = .systemGreen
        } else {
            permissionStatusLabel.stringValue = "Accessibility: Required to read and focus windows"
            permissionStatusLabel.textColor = .systemOrange
        }
    }
}
