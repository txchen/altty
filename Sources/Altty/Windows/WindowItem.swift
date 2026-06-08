import AppKit
import ApplicationServices

struct WindowItem: Identifiable {
    let id: String
    let title: String
    let applicationName: String
    let applicationIcon: NSImage
    let runningApplication: NSRunningApplication
    let axWindow: AXUIElement
    let isMinimized: Bool
}
