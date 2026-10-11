import AppKit
import Carbon.HIToolbox

@MainActor
protocol HintWorkspace: AnyObject {
    var frontmostPID: pid_t? { get }
    var doubleClickInterval: TimeInterval { get }
    /// Secure Event Input hides every key from event taps.
    var isSecureInputEnabled: Bool { get }
    /// At most one observer; starting again replaces it. The handler receives
    /// the activated application's process identifier.
    func observeActivations(_ handler: @escaping @MainActor (pid_t?) -> Void)
    func stopObservingActivations()
    func beep()
}

@MainActor
protocol HintClock: AnyObject {
    var now: TimeInterval { get }
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void)
}

@MainActor
final class SystemHintWorkspace: HintWorkspace {
    private var observer: (any NSObjectProtocol)?

    var frontmostPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var doubleClickInterval: TimeInterval { NSEvent.doubleClickInterval }
    var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }

    func observeActivations(_ handler: @escaping @MainActor (pid_t?) -> Void) {
        stopObservingActivations()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = application?.processIdentifier
            MainActor.assumeIsolated { handler(pid) }
        }
    }

    func stopObservingActivations() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    func beep() {
        NSSound.beep()
    }
}

@MainActor
final class SystemHintClock: HintClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            work()
        }
    }
}
