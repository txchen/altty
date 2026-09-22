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
    private var identities = WorkspaceIdentityRegistry<ObjectIdentifier>()
    private var applications: [ObjectIdentifier: NSRunningApplication] = [:]

    func runningApplications() -> [WorkspaceApplicationFacts] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard let pid = admit(application) else { return nil }
            return Self.facts(application, pid: pid)
        }
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
        _ = runningApplications()
        let center = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.didLaunchApplicationNotification, center: center, admission: true) { application, pid in
            onEvent(.launched(Self.facts(application, pid: pid)))
        }
        observe(NSWorkspace.didTerminateApplicationNotification, center: center, termination: true) { _, pid in
            onEvent(.terminated(pid: pid))
        }
        observe(NSWorkspace.didHideApplicationNotification, center: center) { _, pid in
            onEvent(.hidden(pid: pid, isHidden: true))
        }
        observe(NSWorkspace.didUnhideApplicationNotification, center: center) { _, pid in
            onEvent(.hidden(pid: pid, isHidden: false))
        }
        observe(NSWorkspace.didActivateApplicationNotification, center: center) { _, pid in
            onEvent(.activated(pid: pid))
        }
    }

    func stopMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll()
        applications.removeAll()
        identities = WorkspaceIdentityRegistry()
    }

    private func key(for application: NSRunningApplication) -> ObjectIdentifier {
        applications.first(where: { $0.value == application })?.key ?? ObjectIdentifier(application)
    }

    private func admit(_ application: NSRunningApplication) -> ProcessID? {
        let key = key(for: application)
        let reportedPID = application.processIdentifier
        let pid = reportedPID > 0 ? reportedPID : (identities.pid(for: key) ?? reportedPID)
        guard ProcessLiveness.isRunning(pid), !application.isTerminated else { return nil }
        identities.admit(key, pid: pid)
        applications[key] = application
        applications = applications.filter { identities.pid(for: $0.key) != nil }
        return pid
    }

    private func observe(
        _ name: NSNotification.Name,
        center: NotificationCenter,
        admission: Bool = false,
        termination: Bool = false,
        handler: @escaping @MainActor (NSRunningApplication, ProcessID) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let key = self.key(for: application)
                let pid: ProcessID?
                if termination {
                    pid = self.identities.terminate(key)
                    self.applications[key] = nil
                } else if admission {
                    pid = self.admit(application)
                } else {
                    pid = self.identities.pid(for: key) ?? self.admit(application)
                }
                guard let pid else { return }
                handler(application, pid)
            }
        }
        notificationTokens.append(token)
    }

    private static func facts(_ application: NSRunningApplication, pid: ProcessID) -> WorkspaceApplicationFacts {
        WorkspaceApplicationFacts(
            pid: pid,
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
