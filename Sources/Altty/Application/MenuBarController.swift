import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let onCommand: (SwitcherCommand) -> Void
    private var statusItem: NSStatusItem?
    private let readinessItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Accessibility: Checking…", action: nil, keyEquivalent: "")
    private let skyLightItem = NSMenuItem(title: "SkyLight: Checking…", action: nil, keyEquivalent: "")
    private let recheckItem = NSMenuItem(title: "Check Readiness", action: #selector(recheck), keyEquivalent: "")
    private let accessibilityActionItem = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(requestAccessibility), keyEquivalent: "")

    init(onCommand: @escaping (SwitcherCommand) -> Void) { self.onCommand = onCommand }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Altty")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        readinessItem.isEnabled = false
        accessibilityItem.isEnabled = false
        skyLightItem.isEnabled = false
        menu.addItem(readinessItem)
        menu.addItem(accessibilityItem)
        menu.addItem(skyLightItem)
        menu.addItem(recheckItem)
        menu.addItem(accessibilityActionItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Altty", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != nil { $0.target = self } }
        item.menu = menu
        statusItem = item
    }

    func update(state: SwitcherPresentationState) {
        readinessItem.title = state.readinessTitle
        accessibilityItem.title = state.accessibilityStatusTitle
        skyLightItem.title = state.skyLightStatusTitle
        accessibilityActionItem.isHidden = !state.showsAccessibilityAction
    }
    @objc private func recheck() { onCommand(.recheckReadiness) }
    @objc private func openSettings() { onCommand(.openSettings) }
    @objc private func requestAccessibility() { onCommand(.requestAccessibility) }
    @objc private func checkForUpdates() { onCommand(.checkForUpdates) }
    @objc private func quit() { onCommand(.quit) }
}
