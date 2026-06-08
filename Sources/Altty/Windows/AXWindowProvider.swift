import AppKit
import ApplicationServices
import UniformTypeIdentifiers

final class AXWindowProvider {
    func collectWindows() -> [WindowItem] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        let items = apps.flatMap { collectWindows(for: $0) }
        return items.sorted { lhs, rhs in
            let lhsScore = WindowActivationHistory.shared.score(for: lhs.runningApplication)
            let rhsScore = WindowActivationHistory.shared.score(for: rhs.runningApplication)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.applicationName != rhs.applicationName { return lhs.applicationName < rhs.applicationName }
            return lhs.title < rhs.title
        }
    }

    private func collectWindows(for app: NSRunningApplication) -> [WindowItem] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute, from: appElement), !windows.isEmpty else {
            return []
        }
        return windows.compactMap { window in
            makeWindowItem(window, app)
        }
    }

    private func makeWindowItem(_ window: AXUIElement, _ app: NSRunningApplication) -> WindowItem? {
        let role: String? = copyAttribute(kAXRoleAttribute, from: window)
        let subrole: String? = copyAttribute(kAXSubroleAttribute, from: window)
        guard role == kAXWindowRole as String else { return nil }
        if let subrole, ![kAXStandardWindowSubrole as String, kAXDialogSubrole as String].contains(subrole) {
            return nil
        }

        let title: String = copyAttribute(kAXTitleAttribute, from: window) ?? ""
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let displayTitle = title.isEmpty ? appName : title
        let isMinimized: Bool = copyAttribute(kAXMinimizedAttribute, from: window) ?? false
        let id = "\(app.processIdentifier)-\(displayTitle)-\(Unmanaged.passUnretained(window).toOpaque())"
        return WindowItem(
            id: id,
            title: displayTitle,
            applicationName: appName,
            applicationIcon: app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle),
            runningApplication: app,
            axWindow: window,
            isMinimized: isMinimized
        )
    }

    private func copyAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else { return nil }

        if T.self == Bool.self {
            return (value as? NSNumber)?.boolValue as? T
        }
        return value as? T
    }
}
