import AppKit
import ApplicationServices

enum WindowFocuser {
    static func focus(_ item: WindowItem) {
        if item.isMinimized {
            AXUIElementSetAttributeValue(item.axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        item.runningApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        AXUIElementPerformAction(item.axWindow, kAXRaiseAction as CFString)
    }
}
