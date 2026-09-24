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
    func raiseWindow(_ identity: WindowIdentity) async
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
    func raiseWindow(_ identity: WindowIdentity) async {}
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
    private let retryDelays: [Duration]
    private let batchFactory: @Sendable ([WindowIdentity]) -> any AXBatchReading
    private var retryWaits: [UUID: (ProcessID, Task<Void, Error>)] = [:]
    private var processRevisions: [ProcessID: UUID] = [:]

    init(
        observationWorker: AccessibilityObservationWorker? = nil,
        isProcessRunning: @escaping @Sendable (ProcessID) -> Bool = ProcessLiveness.isRunning,
        retryDelays: [Duration] = [.milliseconds(150), .milliseconds(500), .seconds(1)],
        batchFactory: @escaping @Sendable ([WindowIdentity]) -> any AXBatchReading = { AXEnrichmentBatch(identities: $0) }
    ) {
        self.observationWorker = observationWorker
        self.isProcessRunning = isProcessRunning
        self.retryDelays = retryDelays
        self.batchFactory = batchFactory
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
        retryWaits.values.forEach { $0.1.cancel() }
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
            var requested = group
            for attempt in 0...retryDelays.count {
                let batch = batchFactory(requested)
                let attempted = requested
                var retry: [WindowIdentity] = []
                while true {
                    guard revision == enrichmentRevision,
                          processRevision == processRevisions[pid] else { return }
                    guard let progress = await queryScheduler.run(pid: pid, operation: { [isProcessRunning] in
                        guard isProcessRunning(pid) else { return AXEnrichmentBatch.Progress.finishedUnavailable(attempted) }
                        return batch.readNext()
                    }) else { return }
                    guard revision == enrichmentRevision,
                          processRevision == processRevisions[pid] else { return }
                    for (identity, patch) in progress.patches {
                        guard revision == enrichmentRevision,
                              processRevision == processRevisions[pid] else { return }
                        if patch.readFailure == .temporarilyUnavailable, attempt < retryDelays.count {
                            retry.append(identity)
                        } else {
                            await onPatch(identity, patch)
                        }
                    }
                    if progress.finished { break }
                }
                guard !retry.isEmpty else { break }
                // The query slot is already free. Only a finite one-shot timer remains.
                guard await waitForRetry(pid: pid, delay: retryDelays[attempt]) else { return }
                requested = retry
            }
        }
    }

    private func waitForRetry(pid: ProcessID, delay: Duration) async -> Bool {
        let id = UUID()
        let wait = Task { try await Task.sleep(for: delay) }
        retryWaits[id] = (pid, wait)
        defer { retryWaits[id] = nil }
        do { try await wait.value; return true } catch { return false }
    }

    func raiseWindow(_ identity: WindowIdentity) async {
        _ = await queryScheduler.run(pid: identity.pid, priority: .interactive) { [isProcessRunning] in
            guard isProcessRunning(identity.pid) else { return false }
            return AXWindowReader.raiseWindow(identity)
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
        retryWaits.values.filter { $0.0 == pid }.forEach { $0.1.cancel() }
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
        let main: Bool? = attribute(window, kAXMainAttribute as CFString, budget: budget)
        let parent: AXUIElement? = attribute(window, kAXParentAttribute as CFString, budget: budget)
        let parentID: WindowID? = parent.flatMap { parent in
            let parentRole: String? = attribute(parent, kAXRoleAttribute as CFString, budget: budget)
            return parentRole == "AXWindow" ? windowID(parent, budget: budget) : nil
        }
        return WindowSemanticPatch(
            title: update(title), role: update(role), subrole: update(subrole),
            isMinimized: update(minimized), isFullscreen: update(fullscreen),
            isTransient: role == nil || budget.expired || budget.failure != nil ? .unavailable
                : .value(WindowQualification.isTransient(role: role, subrole: subrole)),
            isMain: update(main), parentWindowID: .value(parentID ?? 0), readFailure: budget.failure
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

    static func raiseWindow(_ identity: WindowIdentity) -> Bool {
        let budget = AXReadBudget()
        guard let window = windowElement(for: identity, budget: budget),
              budget.prepare(window) else { return false }
        // A best-effort ordering step. Exact focus is still checked separately;
        // unsupported AXRaise alone must not turn a successful focus into an error.
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
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
        let error = copyWindowID(element, &wid)
        budget.record(error)
        return error == .success && wid != 0 ? wid : nil
    }

    private static func windowElements(application: AXUIElement, budget: AXReadBudget) -> [AXElementBox] {
        var value: CFTypeRef?
        guard budget.prepare(application) else { return [] }
        let error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        budget.record(error)
        guard error == .success, let windows = value as? [AXUIElement] else { return [] }
        return windows.map(AXElementBox.init)
    }

    private static func attribute<Value>(_ element: AXUIElement, _ name: CFString, budget: AXReadBudget) -> Value? {
        var value: CFTypeRef?
        guard budget.prepare(element) else { return nil }
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        budget.record(error)
        guard error == .success else { return nil }
        return value as? Value
    }

    private static func update<Value>(_ value: Value?) -> FieldUpdate<Value>
    where Value: Equatable & Sendable {
        value.map(FieldUpdate.value) ?? .unavailable
    }
}

/// A batch owns AX references on sequential scheduler jobs only. Each slice has a
/// total IPC budget; traversal resumes where it stopped and yields its PID slot.
protocol AXBatchReading: Sendable {
    func readNext() -> AXEnrichmentBatch.Progress
}

final class AXEnrichmentBatch: AXBatchReading, @unchecked Sendable {
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
            for identity in remaining.values {
                var patch = WindowSemanticPatch.unavailable
                patch.readFailure = budget.failure ?? .temporarilyUnavailable
                patches[identity] = patch
            }
            remaining.removeAll()
            self.windows = nil
        }
        return Progress(patches: patches, finished: finished)
    }
}

struct AXReadBudget {
    private final class Status {
        var failure: AccessibilityReadFailure?
    }
    private let status = Status()
    var failure: AccessibilityReadFailure? { status.failure }
    func record(_ error: AXError) {
        switch error {
        case .success, .attributeUnsupported, .noValue, .notImplemented: break
        case .cannotComplete:
            if status.failure == nil { status.failure = .temporarilyUnavailable }
        case .invalidUIElement: status.failure = .invalidElement
        default: if status.failure == nil { status.failure = .permanent }
        }
    }
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
        guard remaining > .zero else { record(.cannotComplete); return false }
        let parts = remaining.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        AXUIElementSetMessagingTimeout(element, Float(min(0.25, seconds)))
        return true
    }
}
