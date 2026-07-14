import AppKit

@MainActor
protocol WorkspaceAdapter: AnyObject, ExceptionsAdapter {
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

    func runningExceptionApplications() -> [ExceptionApplication] {
        NSWorkspace.shared.runningApplications.compactMap(Self.exceptionApplication)
    }

    func exceptionApplication(bundleIdentifier: String) -> ExceptionApplication? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }
        return Self.exceptionApplication(at: url)
    }

    func exceptionApplication(at bundleURL: URL) -> ExceptionApplication? {
        Self.exceptionApplication(at: bundleURL)
    }

    func frontmostApplicationBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
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
            applicationName: application.localizedName,
            bundlePath: application.bundleURL?.path,
            isHidden: application.isHidden,
            isFrontmost: application.isActive
        )
    }

    private static func exceptionApplication(
        _ application: NSRunningApplication
    ) -> ExceptionApplication? {
        guard let bundleIdentifier = application.bundleIdentifier else { return nil }
        return ExceptionApplication(
            bundleIdentifier: bundleIdentifier,
            name: application.localizedName ?? bundleIdentifier,
            bundlePath: application.bundleURL?.path
        )
    }

    private static func exceptionApplication(at bundleURL: URL) -> ExceptionApplication? {
        guard let bundle = Bundle(url: bundleURL),
              let bundleIdentifier = bundle.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
        return ExceptionApplication(
            bundleIdentifier: bundleIdentifier,
            name: name,
            bundlePath: bundleURL.path
        )
    }
}
