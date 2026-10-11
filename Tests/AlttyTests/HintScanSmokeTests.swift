import AppKit
import ApplicationServices
import Testing
@testable import Altty

@MainActor
struct HintScanSmokeTests {
    @Test func realScanFindsTargetsInTheChosenApplication() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ALTTY_RUN_HINT_SCAN_SMOKE"] == "1" else { return }
        let pid = try #require(
            environment["ALTTY_HINT_SCAN_PID"].flatMap { pid_t($0) }
                ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
        let scanner = AXHintScanner()
        let started = ContinuousClock.now
        let result = await withCheckedContinuation { continuation in
            scanner.scan(pid: pid) { continuation.resume(returning: $0) }
        }
        let elapsed = started.duration(to: .now)
        let histogram = Dictionary(grouping: result.targets, by: \.role)
            .map { "\($0.key)=\($0.value.count)" }
            .sorted()
            .joined(separator: " ")
        let name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?"
        print("""
        hint scan smoke: pid=\(pid) app=\(name) trusted=\(AXIsProcessTrusted()) \
        targets=\(result.targets.count) visits=\(result.visits) webArea=\(result.sawWebArea) \
        elapsedMs=\(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        roles: \(histogram)
        """)
        #expect(result.targets.count > 0)
    }
}
