import AppKit

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarControllerDidRequestSwitcher(_ controller: MenuBarController)
    func menuBarControllerDidRequestSettings(_ controller: MenuBarController)
    func menuBarControllerDidRequestQuit(_ controller: MenuBarController)
}

final class MenuBarController: NSObject {
    weak var delegate: MenuBarControllerDelegate?
    private var statusItem: NSStatusItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Altty")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Altty", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showSwitcher() {
        delegate?.menuBarControllerDidRequestSwitcher(self)
    }

    @objc private func showSettings() {
        delegate?.menuBarControllerDidRequestSettings(self)
    }

    @objc private func quit() {
        delegate?.menuBarControllerDidRequestQuit(self)
    }
}
