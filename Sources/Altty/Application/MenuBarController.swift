import AppKit

struct MenuBarObservedState: Equatable {
    let readinessTitle: String
    let statusTitles: [String]
    let actionTitles: [String]
    let showsAccessibilityAction: Bool
    var mouseScrollReversed: Bool = false
}

@MainActor
final class MenuBarController: NSObject {
    private let onCommand: (SwitcherCommand) -> Void
    private var statusItem: NSStatusItem?
    private let readinessItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let accessibilityActionItem = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(requestAccessibility), keyEquivalent: "")
    private let mouseScrollItem = NSMenuItem(title: "Reverse Mouse Scrolling", action: #selector(toggleMouseScroll), keyEquivalent: "")
    private var generalSettings = GeneralSettings.defaults
    private var menu: NSMenu?

    init(onCommand: @escaping (SwitcherCommand) -> Void) { self.onCommand = onCommand }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = AlttyIcon.window()
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        readinessItem.isEnabled = false
        menu.addItem(readinessItem)
        menu.addItem(accessibilityActionItem)
        menu.addItem(.separator())
        menu.addItem(mouseScrollItem)
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Altty", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != nil { $0.target = self } }
        item.menu = menu
        self.menu = menu
        statusItem = item
    }

    var observedState: MenuBarObservedState {
        MenuBarObservedState(
            readinessTitle: readinessItem.title,
            statusTitles: [readinessItem.title],
            actionTitles: menu?.items.compactMap { item in
                guard item.action != nil, !item.isHidden else { return nil }
                return item.title
            } ?? [],
            showsAccessibilityAction: !accessibilityActionItem.isHidden,
            mouseScrollReversed: mouseScrollItem.state == .on
        )
    }

    func uninstall() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        menu = nil
    }

    func update(state: SwitcherPresentationState) {
        generalSettings = state.generalSettings.displayed
        mouseScrollItem.state = generalSettings.reverseMouseWheel ? .on : .off
        readinessItem.title = state.readinessTitle
        accessibilityActionItem.isHidden = !state.showsAccessibilityAction
    }
    @objc func toggleMouseScroll() {
        onCommand(.replaceGeneralSettings(GeneralSettings(
            launchAtLogin: generalSettings.launchAtLogin,
            listPresentation: generalSettings.listPresentation,
            reverseMouseWheel: !generalSettings.reverseMouseWheel)))
    }
    @objc private func openSettings() { onCommand(.openSettings) }
    @objc private func requestAccessibility() { onCommand(.requestAccessibility) }
    @objc private func quit() { onCommand(.quit) }
}
