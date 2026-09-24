import AppKit
import Darwin
@testable import Altty

@main struct SelfWindowFocusProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let ax = SystemAccessibilityAdapter()
            let executor = WindowFocusExecutor(windowServer: SystemWindowServerAdapter(), accessibility: ax)
            let original = await ax.focusedWindow()
            let windows = (0..<2).map { index in
                let window = NSWindow(contentRect: .init(x: 150 + index * 80, y: 200, width: 360, height: 200),
                                      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                window.title = "Self-window regression \(index)"
                window.isReleasedWhenClosed = false
                window.makeKeyAndOrderFront(nil)
                return window
            }
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(200))
            for iteration in 0..<20 {
                let window = windows[iteration % 2]
                let target = WindowIdentity(wid: WindowID(window.windowNumber), pid: getpid(), generation: 1)
                // This exact production call crashed before the fix: local AXRaise
                // entered AppKit directly from AccessibilityQueryScheduler's worker.
                guard await executor.focus(target) else {
                    print("SELF_FOCUS_FAILED: focus sequence")
                    exit(1)
                }
                guard NSApp.keyWindow?.windowNumber == window.windowNumber else {
                    print("SELF_FOCUS_FAILED: wrong key window")
                    exit(1)
                }
                if iteration % 5 == 0 {
                    window.miniaturize(nil)
                    guard await ax.deminimize(target), !window.isMiniaturized else {
                        print("SELF_FOCUS_FAILED: deminimize")
                        exit(1)
                    }
                }
                let patches = await ax.enrichments(for: [target])
                guard patches[target] != nil else { exit(1) }
                guard await ax.focusedWindow() == FocusedWindow(wid: target.wid, pid: target.pid) else {
                    print("SELF_FOCUS_FAILED: focused PID/WID postcondition")
                    exit(1)
                }
            }
            windows.forEach { $0.close() }
            if let original {
                _ = await executor.focus(.init(wid: original.wid, pid: original.pid, generation: 1))
            }
            print("SELF_FOCUS_PASSED: 20 own-window raises, 4 restorations, enrichment and focus reads")
            exit(0)
        }
        NSApp.run()
    }
}
