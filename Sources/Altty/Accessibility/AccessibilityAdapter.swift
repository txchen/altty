import ApplicationServices
import Foundation

@MainActor
protocol AccessibilityAdapter: AnyObject {
    func availability() -> Availability
    func requestPermission()
}

@MainActor
final class SystemAccessibilityAdapter: AccessibilityAdapter {
    func availability() -> Availability { AXIsProcessTrusted() ? .available : .unavailable }
    func requestPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
    }
}
