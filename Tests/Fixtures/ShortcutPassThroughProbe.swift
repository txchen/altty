import AppKit
import Carbon.HIToolbox

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var monitor: Any?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard
            let outputPath = ProcessInfo.processInfo.environment["ALTTY_SHORTCUT_PROBE_OUTPUT"],
            let readyPath = ProcessInfo.processInfo.environment["ALTTY_SHORTCUT_PROBE_READY"]
        else {
            NSApplication.shared.terminate(nil)
            return
        }

        FileManager.default.createFile(atPath: outputPath, contents: Data())
        let outputURL = URL(fileURLWithPath: outputPath)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.option),
                  [UInt16(kVK_Tab), UInt16(kVK_ANSI_Grave)].contains(event.keyCode)
            else {
                return event
            }
            if let handle = try? FileHandle(forWritingTo: outputURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data("\(event.keyCode)\n".utf8))
                try? handle.close()
            }
            return event
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Altty Shortcut Pass-Through Probe"
        let instructions = NSTextField(labelWithString: "Press Option-Tab, then Option-Grave")
        instructions.alignment = .center
        instructions.frame = NSRect(x: 10, y: 45, width: 220, height: 22)
        window.contentView?.addSubview(instructions)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        try? Data("ready".utf8).write(to: URL(fileURLWithPath: readyPath), options: .atomic)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

@main
@MainActor
private enum ShortcutPassThroughProbe {
    static func main() {
        let application = NSApplication.shared
        let delegate = ProbeDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
