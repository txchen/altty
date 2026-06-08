import AppKit

final class WindowActivationHistory {
    static let shared = WindowActivationHistory()

    private var counter = 0
    private var scoresByPid = [pid_t: Int]()

    private init() {
        recordFrontmostApplication()
    }

    func recordFrontmostApplication() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        counter += 1
        scoresByPid[pid] = counter
    }

    func score(for app: NSRunningApplication) -> Int {
        scoresByPid[app.processIdentifier] ?? 0
    }
}
