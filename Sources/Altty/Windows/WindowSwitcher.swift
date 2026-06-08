import AppKit

final class WindowSwitcher {
    private let provider = AXWindowProvider()
    private lazy var panelController = SwitcherWindowController()

    func showOrCycle() {
        if panelController.isVisible {
            panelController.selectNext()
            return
        }
        let windows = provider.collectWindows()
        guard !windows.isEmpty else {
            NSSound.beep()
            return
        }
        panelController.onFocus = { item in
            WindowFocuser.focus(item)
        }
        panelController.show(windows: windows)
    }

    func focusSelectionIfVisible() {
        panelController.focusSelectionIfVisible()
    }
}
