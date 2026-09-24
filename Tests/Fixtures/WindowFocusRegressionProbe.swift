// Real AppKit focus regression. Run only with disposable fixture window reports.
import AppKit
import Foundation
import ApplicationServices
import Darwin
@testable import Altty

@main struct WindowFocusRegressionProbe {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let ws = SystemWindowServerAdapter()
        let ax = SystemAccessibilityAdapter()
        guard ax.availability() == .available else {
            print("SKIPPED: focus probe requires Accessibility permission")
            exit(77)
        }
        let executor = WindowFocusExecutor(windowServer: ws, accessibility: ax)
        let origin = await ax.focusedWindow()
        var targets: [WindowIdentity] = []
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let report = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let pid = report["pid"] as! Int32
            let windows = report["windows"] as! [UInt32]
            targets += windows.map { .init(wid: $0, pid: pid, generation: 1) }
        }
        guard targets.count >= 4, Set(targets.map(\.pid)).count >= 2 else {
            print("FAIL: requires two disposable apps, each with multiple windows")
            exit(2)
        }
        var failures = 0
        var latencies: [Double] = []
        // Forward/reverse traversal exercises same-app and cross-app transitions.
        for target in targets + targets.reversed() + targets + targets.reversed() {
            let start = ContinuousClock.now
            let sent = await executor.focus(target)
            var observed: FocusedWindow?
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(25))
                observed = await ax.focusedWindow()
                if observed == FocusedWindow(wid: target.wid, pid: target.pid) { break }
            }
            let elapsed = start.duration(to: .now).components
            let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            latencies.append(milliseconds)
            let correct = sent && observed == FocusedWindow(wid: target.wid, pid: target.pid)
            if !correct { failures += 1 }
            print("focus verified=\(correct) target=\(target.pid)/\(target.wid) observed=\(String(describing: observed)) ms=\(Int(milliseconds))")
        }
        for target in [targets[0], targets[targets.count - 1]] {
            if let window = fixtureElement(target),
               AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                try await Task.sleep(for: .milliseconds(300))
                let restored = await ax.deminimize(target)
                let sent = await executor.focus(target)
                var correct = false
                for _ in 0..<20 {
                    try await Task.sleep(for: .milliseconds(25))
                    if await ax.focusedWindow() == FocusedWindow(wid: target.wid, pid: target.pid) {
                        correct = true; break
                    }
                }
                if !restored || !sent || !correct { failures += 1 }
                print("minimized_restore verified=\(restored && sent && correct)")
            } else {
                failures += 1
                print("FAIL: fixture did not accept minimize")
            }
        }
        if let origin {
            _ = await executor.focus(.init(wid: origin.wid, pid: origin.pid, generation: 1))
        }
        print("FOCUS_RESULT attempts=\(latencies.count) failures=\(failures) max_ms=\(Int(latencies.max() ?? 0))")
        exit(failures == 0 ? 0 : 1)
    }
    private static func fixtureElement(_ identity: WindowIdentity) -> AXUIElement? {
        let application = AXUIElementCreateApplication(identity.pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let handle = dlopen(nil, RTLD_LAZY), let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        defer { dlclose(handle) }
        typealias Lookup = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
        let lookup = unsafeBitCast(symbol, to: Lookup.self)
        return windows.first { window in
            var wid: UInt32 = 0
            return lookup(window, &wid) == .success && wid == identity.wid
        }
    }
}
