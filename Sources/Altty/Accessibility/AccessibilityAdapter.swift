import AppKit
import ApplicationServices
import Darwin
import Foundation

enum AccessibilityInventoryEvent: Equatable, Sendable {
    case created(pid: ProcessID, wid: WindowID?)
    case destroyed(pid: ProcessID, wid: WindowID?)
    case focused(pid: ProcessID, wid: WindowID?)
    case semanticsChanged(pid: ProcessID, wid: WindowID?)
}

@MainActor
protocol AccessibilityAdapter: AnyObject {
    func availability() -> Availability
    func requestPermission()
    func startMonitoringAvailability(_ onChange: @escaping (Availability) -> Void)
    func stopMonitoringAvailability()
    func releaseObservers()
    func enrichment(for identity: WindowIdentity) async -> WindowSemanticPatch
    func deminimize(_ identity: WindowIdentity) async -> Bool
    func focusedWindow() async -> FocusedWindow?
    func startMonitoringInventory(_ onEvent: @escaping @MainActor (AccessibilityInventoryEvent) -> Void)
    func observeApplication(pid: ProcessID)
    func stopMonitoringInventory()
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
    private struct ObserverRegistration {
        let observer: AXObserver
        let context: Unmanaged<AXObserverContext>
    }

    private var inventoryEventHandler: (@MainActor (AccessibilityInventoryEvent) -> Void)?
    private var elementObservers: [ProcessID: ObserverRegistration] = [:]

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
        for registration in elementObservers.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(registration.observer),
                .commonModes
            )
            registration.context.release()
        }
        elementObservers.removeAll()
    }

    func enrichment(for identity: WindowIdentity) async -> WindowSemanticPatch {
        await Task.detached(priority: .userInitiated) {
            AXWindowReader.semanticPatch(for: identity)
        }.value
    }

    func deminimize(_ identity: WindowIdentity) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            AXWindowReader.deminimize(identity)
        }.value
    }

    func focusedWindow() async -> FocusedWindow? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let focusedWindow = await Task.detached(priority: .userInitiated) {
            AXWindowReader.focusedWindow(pid: pid)
        }.value
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        return focusedWindow
    }

    func startMonitoringInventory(
        _ onEvent: @escaping @MainActor (AccessibilityInventoryEvent) -> Void
    ) {
        stopMonitoringInventory()
        inventoryEventHandler = onEvent
        for application in NSWorkspace.shared.runningApplications {
            observeApplication(pid: application.processIdentifier)
        }
    }

    func observeApplication(pid: ProcessID) {
        guard pid > 0, elementObservers[pid] == nil, let inventoryEventHandler else { return }
        let context = Unmanaged.passRetained(AXObserverContext(pid: pid) { event in
            Task { @MainActor in inventoryEventHandler(event) }
        })
        var observer: AXObserver?
        let error = AXObserverCreate(pid, Self.inventoryObserverCallback, &observer)
        guard error == .success, let observer else {
            context.release()
            return
        }

        let application = AXUIElementCreateApplication(pid)
        let pointer = context.toOpaque()
        let appNotifications: [CFString] = [
            kAXWindowCreatedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString,
        ]
        for notification in appNotifications {
            AXObserverAddNotification(observer, application, notification, pointer)
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        elementObservers[pid] = ObserverRegistration(observer: observer, context: context)

        Task {
            let windows = await Task.detached(priority: .utility) {
                AXWindowReader.windowElements(pid: pid)
            }.value
            guard self.elementObservers[pid]?.observer === observer else { return }
            for box in windows {
                Self.addWindowNotifications(observer: observer, window: box.element, context: pointer)
            }
        }
    }

    func stopMonitoringInventory() {
        releaseObservers()
        inventoryEventHandler = nil
    }

    private nonisolated static let inventoryObserverCallback: AXObserverCallback = {
        observer, element, notification, contextPointer in
        guard let contextPointer else { return }
        let context = Unmanaged<AXObserverContext>.fromOpaque(contextPointer).takeUnretainedValue()
        let notificationName = notification as String
        let wid = AXWindowReader.windowID(element)

        if notificationName == kAXWindowCreatedNotification {
            addWindowNotifications(observer: observer, window: element, context: contextPointer)
            context.publish(.created(pid: context.pid, wid: wid))
        } else if notificationName == kAXFocusedWindowChangedNotification {
            context.publish(.focused(pid: context.pid, wid: wid))
        } else if notificationName == kAXUIElementDestroyedNotification {
            context.publish(.destroyed(pid: context.pid, wid: wid))
        } else {
            context.publish(.semanticsChanged(pid: context.pid, wid: wid))
        }
    }

    private nonisolated static func addWindowNotifications(
        observer: AXObserver,
        window: AXUIElement,
        context: UnsafeMutableRawPointer
    ) {
        let notifications: [CFString] = [
            kAXUIElementDestroyedNotification as CFString,
            kAXTitleChangedNotification as CFString,
            kAXWindowMiniaturizedNotification as CFString,
            kAXWindowDeminiaturizedNotification as CFString,
        ]
        for notification in notifications {
            let error = AXObserverAddNotification(observer, window, notification, context)
            if error == .notificationAlreadyRegistered { continue }
        }
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

private final class AXObserverContext: @unchecked Sendable {
    let pid: ProcessID
    private let onEvent: @Sendable (AccessibilityInventoryEvent) -> Void

    init(pid: ProcessID, onEvent: @escaping @Sendable (AccessibilityInventoryEvent) -> Void) {
        self.pid = pid
        self.onEvent = onEvent
    }

    func publish(_ event: AccessibilityInventoryEvent) { onEvent(event) }
}

private struct AXElementBox: @unchecked Sendable {
    let element: AXUIElement
}

private enum AXWindowReader {
    private typealias CopyWindowID = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<WindowID>
    ) -> AXError
    private static let copyWindowID: CopyWindowID? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: CopyWindowID.self)
    }()

    static func semanticPatch(for identity: WindowIdentity) -> WindowSemanticPatch {
        guard let window = windowElement(for: identity) else {
            return WindowSemanticPatch(
                title: .unavailable,
                role: .unavailable,
                subrole: .unavailable,
                isMinimized: .unavailable,
                isFullscreen: .unavailable,
                isTransient: .unavailable
            )
        }

        let title: String? = attribute(window, kAXTitleAttribute as CFString)
        let role: String? = attribute(window, kAXRoleAttribute as CFString)
        let subrole: String? = attribute(window, kAXSubroleAttribute as CFString)
        let minimized: Bool? = attribute(window, kAXMinimizedAttribute as CFString)
        let fullscreen: Bool? = attribute(window, "AXFullScreen" as CFString)
        let transient = WindowQualification.isTransient(role: role, subrole: subrole)

        return WindowSemanticPatch(
            title: update(title),
            role: update(role),
            subrole: update(subrole),
            isMinimized: update(minimized),
            isFullscreen: update(fullscreen),
            isTransient: .value(transient)
        )
    }

    static func deminimize(_ identity: WindowIdentity) -> Bool {
        guard let window = windowElement(for: identity) else { return false }
        let minimized: Bool? = attribute(window, kAXMinimizedAttribute as CFString)
        if minimized == false { return true }
        guard AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        ) == .success else { return false }
        let updated: Bool? = attribute(window, kAXMinimizedAttribute as CFString)
        return updated == false
    }

    static func focusedWindow(pid: ProcessID) -> FocusedWindow? {
        guard pid > 0 else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        let window: AXUIElement? = attribute(application, kAXFocusedWindowAttribute as CFString)
        guard let window, let wid = windowID(window) else { return nil }
        return FocusedWindow(wid: wid, pid: pid)
    }

    private static func windowElement(for identity: WindowIdentity) -> AXUIElement? {
        let application = AXUIElementCreateApplication(identity.pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        let window = windowElements(application: application).first(where: {
            windowID($0.element) == identity.wid
        })?.element
        if let window { AXUIElementSetMessagingTimeout(window, 0.25) }
        return window
    }

    static func windowElements(pid: ProcessID) -> [AXElementBox] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        return windowElements(application: application)
    }

    static func windowID(_ element: AXUIElement) -> WindowID? {
        guard let copyWindowID else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.25)
        var wid: WindowID = 0
        return copyWindowID(element, &wid) == .success && wid != 0 ? wid : nil
    }

    private static func windowElements(application: AXUIElement) -> [AXElementBox] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.map(AXElementBox.init)
    }

    private static func attribute<Value>(_ element: AXUIElement, _ name: CFString) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? Value
    }

    private static func update<Value>(_ value: Value?) -> FieldUpdate<Value>
    where Value: Equatable & Sendable {
        value.map(FieldUpdate.value) ?? .unavailable
    }
}
