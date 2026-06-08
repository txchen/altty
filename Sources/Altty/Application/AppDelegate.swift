import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()
    private let hotKeyController = HotKeyController()
    private let switcher = WindowSwitcher()
    private let settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.delegate = self
        menuBarController.install()
        hotKeyController.delegate = self
        hotKeyController.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        if !AccessibilityPermission.isTrusted {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController.stop()
    }

    @objc private func activeApplicationDidChange(_ notification: Notification) {
        WindowActivationHistory.shared.recordFrontmostApplication()
    }

    private func showSwitcher() {
        guard AccessibilityPermission.isTrusted else {
            showSettings()
            AccessibilityPermission.request()
            return
        }
        switcher.showOrCycle()
    }
}

extension AppDelegate: MenuBarControllerDelegate {
    func menuBarControllerDidRequestSwitcher(_ controller: MenuBarController) {
        showSwitcher()
    }

    func menuBarControllerDidRequestSettings(_ controller: MenuBarController) {
        showSettings()
    }

    func menuBarControllerDidRequestQuit(_ controller: MenuBarController) {
        NSApp.terminate(nil)
    }

    private func showSettings() {
        settingsWindowController.show()
    }
}

extension AppDelegate: HotKeyControllerDelegate {
    func hotKeyControllerDidTriggerNextWindow(_ controller: HotKeyController) {
        showSwitcher()
    }

    func hotKeyControllerDidReleaseHoldModifier(_ controller: HotKeyController) {
        switcher.focusSelectionIfVisible()
    }
}
