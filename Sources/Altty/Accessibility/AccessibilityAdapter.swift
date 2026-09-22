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
    func enrichments(for identities: [WindowIdentity]) async -> [WindowIdentity: WindowSemanticPatch]
    func enrichments(for identities: [WindowIdentity], onPatch: @escaping @MainActor (WindowIdentity, WindowSemanticPatch) async -> Void) async
    func cancelPendingEnrichment()
    func enrichment(for identity: WindowIdentity) async -> WindowSemanticPatch
    func deminimize(_ identity: WindowIdentity) async -> Bool
    func focusedWindow() async -> FocusedWindow?
    func startMonitoringInventory(_ onEvent: @escaping @MainActor (AccessibilityInventoryEvent) -> Void)
    func observeApplication(pid: ProcessID)
    func stopObservingApplication(pid: ProcessID)
    func stopMonitoringInventory()
}

extension AccessibilityAdapter {
    func enrichments(for identities: [WindowIdentity]) async -> [WindowIdentity: WindowSemanticPatch] {
        var result: [WindowIdentity: WindowSemanticPatch] = [:]
        for identity in identities { result[identity] = await enrichment(for: identity) }
        return result
    }
    func enrichments(for identities: [WindowIdentity], onPatch: @escaping @MainActor (WindowIdentity, WindowSemanticPatch) async -> Void) async {
        for (identity, patch) in await enrichments(for: identities) { await onPatch(identity, patch) }
    }
    func cancelPendingEnrichment() {}
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
    private var inventoryEventHandler: (@MainActor (AccessibilityInventoryEvent) -> Void)?
    private var observationTokens: [ProcessID: UUID] = [:]
    private var observationWorker: AccessibilityObservationWorker?
    private let queryScheduler = AccessibilityQueryScheduler()
    private let isProcessRunning: @Sendable (ProcessID) -> Bool
    private var enrichmentRevision: UInt64 = 0
    private var processRevisions: [ProcessID: UUID] = [:]

    init(
        observationWorker: AccessibilityObservationWorker? = nil,
        isProcessRunning: @escaping @Sendable (ProcessID) -> Bool = ProcessLiveness.isRunning
    ) {
        self.observationWorker = observationWorker
        self.isProcessRunning = isProcessRunning
    }

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
        cancelPendingEnrichment()
        observationTokens.removeAll()
        processRevisions.removeAll()
        observationWorker?.removeAll()
    }

    func cancelPendingEnrichment() {
        enrichmentRevision &+= 1
        queryScheduler.cancel()
    }

    func enrichment(for identity: WindowIdentity) async -> WindowSemanticPatch {
        await enrichments(for: [identity])[identity] ?? .unavailable
    }

    func enrichments(for identities: [WindowIdentity]) async -> [WindowIdentity: WindowSemanticPatch] {
        var result: [WindowIdentity: WindowSemanticPatch] = [:]
        await enrichments(for: identities) { identity, patch in result[identity] = patch }
        return result
    }

    func enrichments(
        for identities: [WindowIdentity],
        onPatch: @escaping @MainActor (WindowIdentity, WindowSemanticPatch) async -> Void
    ) async {
        let revision = enrichmentRevision
        for group in Dictionary(grouping: identities, by: \.pid).values {
            guard let pid = group.first?.pid, isProcessRunning(pid) else {
                for identity in group { await onPatch(identity, .unavailable) }
                continue
            }
            let processRevision = processRevisions[pid] ?? UUID()
            processRevisions[pid] = processRevision
            let batch = AXEnrichmentBatch(identities: group)
            while true {
                guard revision == enrichmentRevision,
                      processRevision == processRevisions[pid] else { return }
                guard let progress = await queryScheduler.run(pid: pid, operation: { [isProcessRunning] in
                    guard isProcessRunning(pid) else { return AXEnrichmentBatch.Progress.finishedUnavailable(group) }
                    return batch.readNext()
                }) else { return }
                guard revision == enrichmentRevision,
                      processRevision == processRevisions[pid] else { return }
                for (identity, patch) in progress.patches {
                    guard revision == enrichmentRevision,
                          processRevision == processRevisions[pid] else { return }
                    await onPatch(identity, patch)
                }
                if progress.finished { break }
            }
        }
    }

    func deminimize(_ identity: WindowIdentity) async -> Bool {
        await queryScheduler.run(pid: identity.pid, priority: .interactive) { [isProcessRunning] in
            isProcessRunning(identity.pid) && AXWindowReader.deminimize(identity)
        } ?? false
    }

    func focusedWindow() async -> FocusedWindow? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let focusedWindow = await queryScheduler.run(pid: pid, priority: .interactive) { [isProcessRunning] in
            isProcessRunning(pid) ? AXWindowReader.focusedWindow(pid: pid) : nil
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        return focusedWindow ?? nil
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
        guard pid > 0, observationTokens[pid] == nil, inventoryEventHandler != nil,
              isProcessRunning(pid) else { return }
        if observationWorker == nil {
            observationWorker = AccessibilityObservationWorker(isProcessRunning: isProcessRunning) { pid, onEvent in
                AXApplicationObservation(pid: pid, onEvent: onEvent)
            }
        }
        let token = UUID()
        observationTokens[pid] = token
        observationWorker?.observe(pid: pid, onEvent: { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.observationTokens[pid] == token else { return }
                self.inventoryEventHandler?(event)
            }
        }, onFailure: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationTokens[pid] == token else { return }
                self.observationTokens[pid] = nil
            }
        })
    }

    func stopObservingApplication(pid: ProcessID) {
        processRevisions[pid] = nil
        queryScheduler.cancel(pid: pid)
        observationTokens[pid] = nil
        observationWorker?.remove(pid: pid)
    }

    func stopMonitoringInventory() {
        releaseObservers()
        inventoryEventHandler = nil
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

private final class AXObserverContext {
    let pid: ProcessID
    private let onEvent: @Sendable (AccessibilityInventoryEvent) -> Void

    init(pid: ProcessID, onEvent: @escaping @Sendable (AccessibilityInventoryEvent) -> Void) {
        self.pid = pid
        self.onEvent = onEvent
    }

    func publish(_ event: AccessibilityInventoryEvent) { onEvent(event) }
}

// All methods, including callbacks and invalidation, run on the observation worker.
private final class AXApplicationObservation: AccessibilityObservationRegistration {
    private let observer: AXObserver
    private let context: AXObserverContext

    init?(pid: ProcessID, onEvent: @escaping @Sendable (AccessibilityInventoryEvent) -> Void) {
        precondition(!Thread.isMainThread)
        let context = AXObserverContext(pid: pid, onEvent: onEvent)
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success,
              let observer = created else { return nil }
        self.observer = observer
        self.context = context
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, application, name as CFString, pointer)
        }
        for window in AXWindowReader.windowElements(pid: pid) {
            Self.addWindowNotifications(observer: observer, window: window.element, context: pointer)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func invalidate() {
        precondition(!Thread.isMainThread)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private static let callback: AXObserverCallback = { observer, element, notification, pointer in
        autoreleasepool {
            precondition(!Thread.isMainThread)
            guard let pointer else { return }
            let context = Unmanaged<AXObserverContext>.fromOpaque(pointer).takeUnretainedValue()
            let wid = AXWindowReader.windowID(element)
            switch notification as String {
            case kAXWindowCreatedNotification:
                addWindowNotifications(observer: observer, window: element, context: pointer)
                context.publish(.created(pid: context.pid, wid: wid))
            case kAXFocusedWindowChangedNotification:
                context.publish(.focused(pid: context.pid, wid: wid))
            case kAXUIElementDestroyedNotification:
                context.publish(.destroyed(pid: context.pid, wid: wid))
            default:
                context.publish(.semanticsChanged(pid: context.pid, wid: wid))
            }
        }
    }

    private static func addWindowNotifications(
        observer: AXObserver,
        window: AXUIElement,
        context: UnsafeMutableRawPointer
    ) {
        AXUIElementSetMessagingTimeout(window, 0.25)
        for name in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, window, name as CFString, context)
        }
    }
}

struct AXElementBox: @unchecked Sendable {
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

    static func semanticPatch(window: AXUIElement, budget: AXReadBudget) -> WindowSemanticPatch {
        let title: String? = attribute(window, kAXTitleAttribute as CFString, budget: budget)
        let role: String? = attribute(window, kAXRoleAttribute as CFString, budget: budget)
        let subrole: String? = attribute(window, kAXSubroleAttribute as CFString, budget: budget)
        let minimized: Bool? = attribute(window, kAXMinimizedAttribute as CFString, budget: budget)
        let fullscreen: Bool? = attribute(window, "AXFullScreen" as CFString, budget: budget)
        return WindowSemanticPatch(
            title: update(title), role: update(role), subrole: update(subrole),
            isMinimized: update(minimized), isFullscreen: update(fullscreen),
            isTransient: role == nil || budget.expired ? .unavailable
                : .value(WindowQualification.isTransient(role: role, subrole: subrole))
        )
    }

    static func deminimize(_ identity: WindowIdentity) -> Bool {
        let budget = AXReadBudget()
        guard let window = windowElement(for: identity, budget: budget) else { return false }
        let minimized: Bool? = attribute(window, kAXMinimizedAttribute as CFString, budget: budget)
        if minimized == false { return true }
        guard budget.prepare(window), AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        ) == .success else { return false }
        let updated: Bool? = attribute(window, kAXMinimizedAttribute as CFString, budget: budget)
        return updated == false
    }

    static func focusedWindow(pid: ProcessID) -> FocusedWindow? {
        guard pid > 0 else { return nil }
        let budget = AXReadBudget()
        let application = AXUIElementCreateApplication(pid)
        let window: AXUIElement? = attribute(application, kAXFocusedWindowAttribute as CFString, budget: budget)
        guard let window, budget.prepare(window), let wid = windowID(window, budget: budget) else { return nil }
        return FocusedWindow(wid: wid, pid: pid)
    }

    private static func windowElement(for identity: WindowIdentity, budget: AXReadBudget) -> AXUIElement? {
        let application = AXUIElementCreateApplication(identity.pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        let window = windowElements(application: application, budget: budget).first(where: {
            windowID($0.element, budget: budget) == identity.wid
        })?.element
        if let window { AXUIElementSetMessagingTimeout(window, 0.25) }
        return window
    }

    static func windowElements(pid: ProcessID, budget: AXReadBudget = AXReadBudget()) -> [AXElementBox] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        return windowElements(application: application, budget: budget)
    }

    static func windowID(_ element: AXUIElement, budget: AXReadBudget = AXReadBudget()) -> WindowID? {
        guard let copyWindowID, budget.prepare(element) else { return nil }
        var wid: WindowID = 0
        return copyWindowID(element, &wid) == .success && wid != 0 ? wid : nil
    }

    private static func windowElements(application: AXUIElement, budget: AXReadBudget) -> [AXElementBox] {
        var value: CFTypeRef?
        guard budget.prepare(application), AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.map(AXElementBox.init)
    }

    private static func attribute<Value>(_ element: AXUIElement, _ name: CFString, budget: AXReadBudget) -> Value? {
        var value: CFTypeRef?
        guard budget.prepare(element), AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? Value
    }

    private static func update<Value>(_ value: Value?) -> FieldUpdate<Value>
    where Value: Equatable & Sendable {
        value.map(FieldUpdate.value) ?? .unavailable
    }
}

/// A batch owns AX references on sequential scheduler jobs only. Each slice has a
/// total IPC budget; traversal resumes where it stopped and yields its PID slot.
final class AXEnrichmentBatch: @unchecked Sendable {
    struct Progress: Sendable {
        let patches: [WindowIdentity: WindowSemanticPatch]
        let finished: Bool
        static func finishedUnavailable(_ identities: [WindowIdentity]) -> Self {
            Self(patches: Dictionary(identities.map { ($0, .unavailable) }, uniquingKeysWith: { a, _ in a }), finished: true)
        }
    }
    private let identities: [WindowIdentity]
    private let enumerate: @Sendable (ProcessID, AXReadBudget) -> [AXElementBox]
    private let identify: @Sendable (AXUIElement, AXReadBudget) -> WindowID?
    private let read: @Sendable (AXUIElement, AXReadBudget) -> WindowSemanticPatch
    private let makeBudget: @Sendable () -> AXReadBudget
    private var remaining: [WindowID: WindowIdentity]
    private var windows: [AXElementBox]?
    private var index = 0
    private var pendingWindow: (AXElementBox, WindowIdentity)?

    init(
        identities: [WindowIdentity],
        enumerate: @escaping @Sendable (ProcessID, AXReadBudget) -> [AXElementBox] = AXWindowReader.windowElements,
        identify: @escaping @Sendable (AXUIElement, AXReadBudget) -> WindowID? = AXWindowReader.windowID,
        read: @escaping @Sendable (AXUIElement, AXReadBudget) -> WindowSemanticPatch = AXWindowReader.semanticPatch,
        makeBudget: @escaping @Sendable () -> AXReadBudget = { AXReadBudget() }
    ) {
        precondition(!identities.isEmpty && Set(identities.map(\.pid)).count == 1)
        self.identities = identities
        self.enumerate = enumerate
        self.identify = identify
        self.read = read
        self.makeBudget = makeBudget
        remaining = Dictionary(identities.map { ($0.wid, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func readNext() -> Progress {
        let budget = makeBudget()
        if windows == nil { windows = enumerate(identities[0].pid, budget) }
        let windows = windows ?? []
        var patches: [WindowIdentity: WindowSemanticPatch] = [:]
        while (!remaining.isEmpty || pendingWindow != nil), !budget.expired {
            if let (window, identity) = pendingWindow {
                patches[identity] = read(window.element, budget)
                pendingWindow = nil
                continue
            }
            guard index < windows.count else { break }
            let window = windows[index]
            let wid = identify(window.element, budget)
            index += 1
            if let wid, let identity = remaining.removeValue(forKey: wid) {
                pendingWindow = (window, identity)
                // A slow lookup must not spend the semantic read's entire budget.
                if budget.remainingSeconds < 0.025 { break }
            }
        }
        let finished = pendingWindow == nil && (index == windows.count || remaining.isEmpty)
        if finished {
            for identity in remaining.values { patches[identity] = .unavailable }
            remaining.removeAll()
            self.windows = nil
        }
        return Progress(patches: patches, finished: finished)
    }
}

struct AXReadBudget {
    private let deadline: ContinuousClock.Instant
    private let now: @Sendable () -> ContinuousClock.Instant
    init(now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.now = now
        deadline = now().advanced(by: .milliseconds(250))
    }
    var expired: Bool { now() >= deadline }
    var remainingSeconds: Double {
        let parts = now().duration(to: deadline).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
    func prepare(_ element: AXUIElement) -> Bool {
        let remaining = now().duration(to: deadline)
        guard remaining > .zero else { return false }
        let parts = remaining.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        AXUIElementSetMessagingTimeout(element, Float(min(0.25, seconds)))
        return true
    }
}
