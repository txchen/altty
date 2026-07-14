import AppKit

@MainActor
protocol WorkspaceAdapter: AnyObject {
    func runningApplications() -> [WorkspaceApplicationFacts]
    func startMonitoring(_ onEvent: @escaping @MainActor (WorkspaceApplicationEvent) -> Void)
    func stopMonitoring()
}

@MainActor
final class SystemWorkspaceAdapter: WorkspaceAdapter {
    private var notificationTokens: [NSObjectProtocol] = []

    func runningApplications() -> [WorkspaceApplicationFacts] {
        NSWorkspace.shared.runningApplications.map(Self.facts)
    }

    func startMonitoring(_ onEvent: @escaping @MainActor (WorkspaceApplicationEvent) -> Void) {
        stopMonitoring()
        let center = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.didLaunchApplicationNotification, center: center) { application in
            onEvent(.launched(Self.facts(application)))
        }
        observe(NSWorkspace.didTerminateApplicationNotification, center: center) { application in
            onEvent(.terminated(pid: application.processIdentifier))
        }
        observe(NSWorkspace.didHideApplicationNotification, center: center) { application in
            onEvent(.hidden(pid: application.processIdentifier, isHidden: true))
        }
        observe(NSWorkspace.didUnhideApplicationNotification, center: center) { application in
            onEvent(.hidden(pid: application.processIdentifier, isHidden: false))
        }
        observe(NSWorkspace.didActivateApplicationNotification, center: center) { application in
            onEvent(.activated(pid: application.processIdentifier))
        }
    }

    func stopMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll()
    }

    private func observe(
        _ name: NSNotification.Name,
        center: NotificationCenter,
        handler: @escaping @MainActor (NSRunningApplication) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            MainActor.assumeIsolated { handler(application) }
        }
        notificationTokens.append(token)
    }

    private static func facts(_ application: NSRunningApplication) -> WorkspaceApplicationFacts {
        WorkspaceApplicationFacts(
            pid: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            isHidden: application.isHidden,
            isFrontmost: application.isActive
        )
    }
}
