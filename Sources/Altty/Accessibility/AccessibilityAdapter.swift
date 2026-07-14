import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol AccessibilityAdapter: AnyObject {
    func availability() -> Availability
    func requestPermission()
    func startMonitoringAvailability(_ onChange: @escaping (Availability) -> Void)
    func stopMonitoringAvailability()
    func releaseObservers()
}

@MainActor
final class SystemAccessibilityAdapter: AccessibilityAdapter {
    private nonisolated static let systemSettingsBundleIdentifier = "com.apple.systempreferences"
    private static let permissionObservationTimeout = DispatchTimeInterval.seconds(120)

    private var lastAvailability: Availability?
    private var onChange: ((Availability) -> Void)?
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var permissionChangeTimer: DispatchSourceTimer?
    private var permissionObservationDeadline: DispatchTime?
    private var elementObservers: [AXObserver] = []

    func availability() -> Availability {
        AXIsProcessTrusted() ? .available : .unavailable
    }

    func requestPermission() {
        beginPermissionChangeObservation(timeout: Self.permissionObservationTimeout)
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
    }

    func startMonitoringAvailability(_ onChange: @escaping (Availability) -> Void) {
        stopMonitoringAvailability()
        self.onChange = onChange
        lastAvailability = availability()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isSystemSettings = application?.bundleIdentifier == Self.systemSettingsBundleIdentifier
            MainActor.assumeIsolated { self?.workspaceApplicationActivated(isSystemSettings: isSystemSettings) }
        }
        notificationTokens.append((workspaceCenter, workspaceToken))

        let applicationCenter = NotificationCenter.default
        let applicationToken = applicationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishAvailabilityIfChanged() }
        }
        notificationTokens.append((applicationCenter, applicationToken))

        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.systemSettingsBundleIdentifier {
            beginPermissionChangeObservation(timeout: nil)
        }
    }

    func stopMonitoringAvailability() {
        stopPermissionChangeObservation()
        notificationTokens.forEach { center, token in center.removeObserver(token) }
        notificationTokens.removeAll()
        onChange = nil
        lastAvailability = nil
    }

    func releaseObservers() {
        for observer in elementObservers {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        elementObservers.removeAll()
    }

    private func publishAvailabilityIfChanged() {
        let current = availability()
        guard current != lastAvailability else { return }
        lastAvailability = current
        onChange?(current)
    }

    private func workspaceApplicationActivated(isSystemSettings: Bool) {
        publishAvailabilityIfChanged()
        if isSystemSettings {
            beginPermissionChangeObservation(timeout: nil)
        } else {
            stopPermissionChangeObservation()
        }
    }

    private func beginPermissionChangeObservation(timeout: DispatchTimeInterval?) {
        stopPermissionChangeObservation()
        permissionObservationDeadline = timeout.map { .now() + $0 }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(500),
            repeating: .seconds(1),
            leeway: .milliseconds(250)
        )
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let deadline = self.permissionObservationDeadline,
                   DispatchTime.now() >= deadline {
                    self.stopPermissionChangeObservation()
                    return
                }
                self.publishAvailabilityIfChanged()
            }
        }
        permissionChangeTimer = timer
        timer.resume()
    }

    private func stopPermissionChangeObservation() {
        permissionChangeTimer?.setEventHandler {}
        permissionChangeTimer?.cancel()
        permissionChangeTimer = nil
        permissionObservationDeadline = nil
    }
}
