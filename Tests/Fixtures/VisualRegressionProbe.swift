import AppKit
@testable import Altty

@MainActor private final class FixedDisplays: SwitcherDisplayProviding {
    var pointerLocation: CGPoint { .init(x: 500, y: 500) }
    var displays: [SwitcherDisplay] { [.init(identifier: "fixture", frame: .init(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: .init(x: 0, y: 0, width: 1440, height: 860), windowServerFrame: .init(x: 0, y: 0, width: 1440, height: 900), isPrimary: true)] }
    func frame(of window: WindowIdentity) -> CGRect? { .init(x: 100, y: 100, width: 600, height: 400) }
}
@MainActor private final class EmptyApps: ExceptionsAdapter {
    func runningExceptionApplications() -> [ExceptionApplication] { [] }
    func exceptionApplication(bundleIdentifier: String) -> ExceptionApplication? { nil }
    func exceptionApplication(at bundleURL: URL) -> ExceptionApplication? { nil }
    func frontmostApplicationBundleIdentifier() -> String? { nil }
}

@main struct VisualRegressionProbe {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for theme in ["light", "dark"] {
            let appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)!
            let panel = SwitcherPanelController(displayProvider: FixedDisplays())
            for scenario in ["short", "cjk", "scroll", "removed"] {
                var rows = (1...(scenario == "scroll" ? 24 : 3)).map { index in
                    SwitcherPanelRow(identity: .init(wid: WindowID(index), pid: 100, generation: 1),
                        title: scenario == "cjk" ? "中文窗口标题 — 日本語テキスト — \(String(repeating: "Long document title ", count: 5))\(index)" : "Document \(index)",
                        applicationName: "Fixture App", applicationBundlePath: nil,
                        isMinimized: index == 2, applicationIsHidden: index == 3, isFullscreen: false)
                }
                let initial = SwitcherPanelState(mode: .allWindows, shortcutDescription: "⌥Tab", rows: rows,
                    selectedIdentity: rows[1].identity)
                panel.show(state: initial)
                if scenario == "removed" { rows.remove(at: 1) }
                let selected = scenario == "scroll" ? rows[20].identity : rows[min(1, rows.count - 1)].identity
                panel.update(state: .init(mode: .allWindows, shortcutDescription: "⌥Tab", rows: rows, selectedIdentity: selected))
                guard let view = panel.tableView.window?.contentView else { fatalError("missing panel") }
                try await capture(view, appearance: appearance, name: "\(scenario)-\(theme)", output: output)
                panel.dismiss()
            }
            let settings = SettingsWindowController(exceptions: EmptyApps(),
                productInformation: .init(name: "Altty", version: "0.0.0", build: "fixture")) { _ in }
            let state = SwitcherPresentationState(hasLaunched: true, accessibility: .available, windowServer: .available)
            settings.update(state: state)
            settings.window?.orderFront(nil)
            let view = settings.window!.contentView!
            try await capture(view, appearance: appearance, name: "settings-\(theme)", output: output)
            if let sidebar = descendants(view).compactMap({ $0 as? NSTableView }).first {
                sidebar.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
                settings.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: sidebar))
            }
            try await capture(view, appearance: appearance, name: "exceptions-\(theme)", output: output)
            if let sidebar = descendants(view).compactMap({ $0 as? NSTableView }).first {
                for (index, name) in [(1, "shortcuts"), (3, "about")] {
                    sidebar.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    settings.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: sidebar))
                    try await capture(view, appearance: appearance, name: "\(name)-\(theme)", output: output)
                }
                var permissionState = state
                permissionState.generalSettings.current = .init(launchAtLogin: false, listPresentation: .defaults, reverseMouseWheel: true)
                permissionState.generalSettings.mouseScrollStatus = .inputMonitoringRequired
                settings.update(state: permissionState)
                sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                settings.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: sidebar))
                try await capture(view, appearance: appearance, name: "permissions-\(theme)", output: output)
            }
            settings.close()
        }
        let manifest: [String: String] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
            "renderer": "AppKit cacheDisplay; synthetic content; inactive within-window material", "scales": "1,2"]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("environment.json"))
        print("Rendered 36 synthetic UI snapshots to \(output.path)")
    }

    @MainActor private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor private static func capture(_ view: NSView, appearance: NSAppearance, name: String, output: URL) async throws {
        view.window?.appearance = appearance
        view.appearance = appearance
        for child in descendants(view) {
            if let effect = child as? NSVisualEffectView {
                effect.state = .inactive
                effect.blendingMode = .withinWindow
            }
            // AppKit source-list selection is a compositor effect that cacheDisplay
            // renders black; exclude that OS-owned effect, retaining cell layout.
            if let table = child as? NSTableView, table.style == .sourceList {
                table.selectionHighlightStyle = .none
            }
            if let image = child as? NSImageView,
               !["settings", "exceptions", "shortcuts", "about", "permissions"].contains(where: { name.hasPrefix($0) }) {
                image.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "Fixture")
            }
        }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        view.layoutSubtreeIfNeeded()
        NSAnimationContext.endGrouping()
        // Two actor/run-loop opportunities after layout and appearance changes.
        try await Task.sleep(for: .milliseconds(20))
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        for scale in [1, 2] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(view.bounds.width) * scale, pixelsHigh: Int(view.bounds.height) * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = view.bounds.size
            appearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: bitmap) }
            // contentView caches omit the NSWindow background; composite it explicitly.
            let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            appearance.performAsCurrentDrawingAppearance {
                context.setFillColor(NSColor.windowBackgroundColor.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            }
            context.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            let flattened = NSBitmapImageRep(cgImage: context.makeImage()!)
            guard let png = flattened.representation(using: .png, properties: [:]) else { fatalError("PNG conversion") }
            try png.write(to: output.appendingPathComponent("\(name)@\(scale)x.png"))
        }
    }
}
