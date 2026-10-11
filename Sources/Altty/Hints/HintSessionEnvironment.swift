import AppKit

@MainActor
protocol HintWorkspace: AnyObject {
    var frontmostPID: pid_t? { get }
    var doubleClickInterval: TimeInterval { get }
    /// At most one observer; starting again replaces it.
    func observeActivations(_ handler: @escaping @MainActor () -> Void)
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

    func observeActivations(_ handler: @escaping @MainActor () -> Void) {
        stopObservingActivations()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
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
