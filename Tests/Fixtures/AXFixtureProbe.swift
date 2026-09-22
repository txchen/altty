import AppKit
import ApplicationServices
import Foundation
@testable import Altty

@main struct AXFixtureProbe {
    @MainActor static func main() async throws {
        let adapter = SystemAccessibilityAdapter()
        guard adapter.availability() == .available else {
            print("AX_SKIPPED: this probe does not have Accessibility permission; no prompt was requested")
            exit(77)
        }
        let report = URL(fileURLWithPath: CommandLine.arguments[1])
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let data = try? Data(contentsOf: report),
               let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               state["phase"] as? String == "stalling",
               let pid = state["pid"] as? Int32, let windows = state["windows"] as? [UInt32], !windows.isEmpty {
                let identities = windows.map { WindowIdentity(wid: $0, pid: pid, generation: 1) }
                let patches = await adapter.enrichments(for: identities)
                guard patches.count == identities.count,
                      patches.values.allSatisfy({ $0.readFailure == nil && $0.role == .value("AXWindow") }) else {
                    let appElement = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(appElement, 0.25)
                    var axValue: CFTypeRef?
                    let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &axValue)
                    print("AX_DIAGNOSTIC enumerationError=\(error.rawValue) count=\((axValue as? [AXUIElement])?.count ?? -1)")
                    for window in (axValue as? [AXUIElement]) ?? [] {
                        for name in ["AXRole"] {
                            var value: CFTypeRef?
                            let result = AXUIElementCopyAttributeValue(window, name as CFString, &value)
                            print("AX_ATTRIBUTE \(name) error=\(result.rawValue) value=\(String(describing: value))")
                        }
                    }
                    for identity in identities {
                        let patch = patches[identity]
                        print("AX_RESULT wid=\(identity.wid) role=\(String(describing: patch?.role)) failure=\(String(describing: patch?.readFailure))")
                    }
                    print("AX_FAILED: windows did not recover within the finite retry budget")
                    exit(1)
                }
                print("AX_PASSED: real fixture recovered during bounded enrichment")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        print("AX_FAILED: fixture never entered the expected stall phase")
        exit(1)
    }
}
