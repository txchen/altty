import AppKit
import CoreFoundation
import Darwin
import Foundation

enum ManagedDisplaySpaceTopology {
    static func currentSpaceIDs(from displays: [[String: Any]]) -> [UInt64] {
        let ids = displays.compactMap { display -> UInt64? in
            guard let currentSpace = display["Current Space"] as? [String: Any] else { return nil }
            if let id = currentSpace["id64"] as? UInt64 { return id }
            if let id = currentSpace["ManagedSpaceID"] as? UInt64 { return id }
            if let id = currentSpace["id64"] as? NSNumber { return id.uint64Value }
            if let id = currentSpace["ManagedSpaceID"] as? NSNumber { return id.uint64Value }
            return nil
        }
        return Array(Set(ids)).sorted()
    }
}

enum WindowServerInventoryEvent: Equatable, Sendable {
    case created(WindowID)
    case destroyed(WindowID)
    case focused(wid: WindowID, pid: ProcessID)
    case semanticsInvalidated(wid: WindowID, pid: ProcessID)
    case activeSpaceChanged
}

@MainActor
protocol WindowServerAdapter: AnyObject {
    func availability() -> Availability
    func activeSpaceSnapshot() async -> WindowServerSnapshot?
    func startMonitoringActiveSpace(_ onChange: @escaping @MainActor () -> Void)
    func stopMonitoringActiveSpace()
    func startMonitoringInventory(_ onEvent: @escaping @MainActor (WindowServerInventoryEvent) -> Void)
    func stopMonitoringInventory()
}

@MainActor
final class SystemWindowServerAdapter: WindowServerAdapter {
    private var activeSpaceObserver: NSObjectProtocol?
    private var inventoryEventHandler: (@MainActor (WindowServerInventoryEvent) -> Void)?
    private var eventTap: SkyLightEventTap?

    func availability() -> Availability {
        SkyLightQuery().isAvailable ? .available : .unavailable
    }

    func activeSpaceSnapshot() async -> WindowServerSnapshot? {
        let snapshot = await Task.detached(priority: .userInitiated) {
            SkyLightQuery().activeSpaceSnapshot()
        }.value
        if let snapshot { eventTap?.subscribe(to: snapshot.windows) }
        return snapshot
    }

    func startMonitoringActiveSpace(_ onChange: @escaping @MainActor () -> Void) {
        stopMonitoringActiveSpace()
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    func stopMonitoringActiveSpace() {
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
        activeSpaceObserver = nil
    }

    func startMonitoringInventory(
        _ onEvent: @escaping @MainActor (WindowServerInventoryEvent) -> Void
    ) {
        inventoryEventHandler = onEvent
        startMonitoringActiveSpace { onEvent(.activeSpaceChanged) }
        if eventTap == nil {
            eventTap = SkyLightEventTap { [weak self] event in
                Task { @MainActor in
                    guard let self, let handler = self.inventoryEventHandler else { return }
                    handler(event)
                }
            }
        }
        eventTap?.isEnabled = true
        Task { [weak self] in
            guard let self, let snapshot = await self.activeSpaceSnapshot() else { return }
            self.eventTap?.subscribe(to: snapshot.windows)
        }
    }

    func stopMonitoringInventory() {
        inventoryEventHandler = nil
        eventTap?.isEnabled = false
        stopMonitoringActiveSpace()
    }
}

private typealias SkyLightNotifyProc = @convention(c) (
    UInt32,
    UnsafeMutableRawPointer?,
    Int,
    UnsafeMutableRawPointer?,
    UInt32
) -> Void

private let skyLightNotifyProc: SkyLightNotifyProc = { event, data, length, context, _ in
    guard let context else { return }
    var wid: WindowID = 0
    if let data, length >= MemoryLayout<WindowID>.size {
        memcpy(&wid, data, MemoryLayout<WindowID>.size)
    }
    Unmanaged<SkyLightEventContext>.fromOpaque(context).takeUnretainedValue().publish(
        rawEvent: event,
        wid: wid
    )
}

private enum SkyLightEventCode: UInt32, CaseIterable {
    case windowDestroyed = 804
    case windowMoved = 806
    case windowResized = 807
    case windowFocused = 808
    case windowCreated = 811
    case windowOrderedIn = 815
    case windowOrderedOut = 816
    case spaceCurrentChanged = 1329
    case activeSpaceChanged = 1401
}

private final class SkyLightEventContext: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    private var processesByWindowID: [WindowID: ProcessID] = [:]
    private let onEvent: @Sendable (WindowServerInventoryEvent) -> Void

    init(onEvent: @escaping @Sendable (WindowServerInventoryEvent) -> Void) {
        self.onEvent = onEvent
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock { self.enabled = enabled }
    }

    func setKnownWindows(_ windows: [WindowServerWindow]) {
        lock.withLock {
            processesByWindowID = Dictionary(
                windows.map { ($0.wid, $0.pid) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    func publish(rawEvent: UInt32, wid: WindowID) {
        let state = lock.withLock { (enabled, processesByWindowID[wid]) }
        guard state.0, let code = SkyLightEventCode(rawValue: rawEvent) else { return }
        let event: WindowServerInventoryEvent?
        switch code {
        case .windowCreated:
            event = wid == 0 ? nil : .created(wid)
        case .windowDestroyed:
            event = wid == 0 ? nil : .destroyed(wid)
        case .windowFocused:
            event = state.1.map { .focused(wid: wid, pid: $0) }
        case .windowMoved, .windowResized, .windowOrderedIn, .windowOrderedOut:
            event = state.1.map { .semanticsInvalidated(wid: wid, pid: $0) }
        case .spaceCurrentChanged, .activeSpaceChanged:
            lock.withLock { processesByWindowID.removeAll() }
            event = .activeSpaceChanged
        }
        if let event { onEvent(event) }
    }
}

private final class SkyLightEventTap: @unchecked Sendable {
    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias RegisterNotification = @convention(c) (
        UInt32,
        SkyLightNotifyProc,
        UInt32,
        UnsafeMutableRawPointer?
    ) -> Int32
    private typealias RequestNotifications = @convention(c) (
        UInt32,
        UnsafeMutablePointer<WindowID>,
        Int32
    ) -> Int32

    private let handle: UnsafeMutableRawPointer
    private let connection: UInt32
    private let requestNotifications: RequestNotifications
    private let context: Unmanaged<SkyLightEventContext>

    var isEnabled: Bool {
        get { true }
        set { context.takeUnretainedValue().setEnabled(newValue) }
    }

    init?(onEvent: @escaping @Sendable (WindowServerInventoryEvent) -> Void) {
        guard let handle = dlopen(SkyLightQuery.frameworkPath, RTLD_NOW | RTLD_LOCAL),
              let mainConnection: MainConnection = Self.load(handle, "CGSMainConnectionID"),
              let register: RegisterNotification = Self.load(handle, "SLSRegisterConnectionNotifyProc"),
              let request: RequestNotifications = Self.load(handle, "SLSRequestNotificationsForWindows") else {
            return nil
        }
        self.handle = handle
        connection = mainConnection()
        requestNotifications = request
        context = .passRetained(SkyLightEventContext(onEvent: onEvent))

        for eventCode in SkyLightEventCode.allCases {
            guard register(connection, skyLightNotifyProc, eventCode.rawValue, context.toOpaque()) == 0 else {
                context.takeUnretainedValue().setEnabled(false)
                return nil
            }
        }
    }

    func subscribe(to windows: [WindowServerWindow]) {
        context.takeUnretainedValue().setKnownWindows(windows)
        var unique = Array(Set(windows.map(\.wid))).filter { $0 != 0 }
        guard !unique.isEmpty else { return }
        _ = requestNotifications(connection, &unique, Int32(unique.count))
    }

    private static func load<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}

private struct SkyLightQuery: Sendable {
    private typealias ConnectionID = UInt32
    private typealias MainConnection = @convention(c) () -> ConnectionID
    private typealias CopyManagedDisplaySpaces = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private typealias CopyWindows = @convention(c) (
        ConnectionID,
        Int,
        CFArray,
        Int,
        UnsafeMutablePointer<Int>,
        UnsafeMutablePointer<Int>
    ) -> Unmanaged<CFArray>?
    private typealias QueryWindows = @convention(c) (
        ConnectionID,
        CFArray,
        Int32
    ) -> Unmanaged<CFTypeRef>?
    private typealias QueryResultCopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias IteratorAdvance = @convention(c) (CFTypeRef) -> Bool
    private typealias IteratorGetWindowID = @convention(c) (CFTypeRef) -> WindowID
    private typealias IteratorGetPID = @convention(c) (CFTypeRef) -> ProcessID

    fileprivate static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let includeInvisibleWindows = 0b111
    private static let requiredSymbols = [
        "CGSMainConnectionID",
        "CGSCopyManagedDisplaySpaces",
        "CGSCopyWindowsWithOptionsAndTags",
        "SLSWindowQueryWindows",
        "SLSWindowQueryResultCopyWindows",
        "SLSWindowIteratorAdvance",
        "SLSWindowIteratorGetWindowID",
        "SLSWindowIteratorGetPID",
        "SLSWindowIteratorGetAttributes",
        "SLSWindowIteratorGetLevel",
        "SLSWindowIteratorGetSpaceTypeMask",
        "SLSWindowIteratorCopyTitle",
        "SLSWindowIteratorGetBounds",
        "_SLPSSetFrontProcessWithOptions",
        "SLSSpaceSetFrontPSN",
        "SLPSPostEventRecordTo",
        "SLSRegisterConnectionNotifyProc",
        "SLSRequestNotificationsForWindows",
    ]

    var isAvailable: Bool {
        withLibrary { handle in
            guard Self.requiredSymbols.allSatisfy({ dlsym(handle, $0) != nil }) else { return false }
            return activeSpaceSnapshot(handle: handle) != nil
        } ?? false
    }

    func activeSpaceSnapshot() -> WindowServerSnapshot? {
        withLibrary { activeSpaceSnapshot(handle: $0) } ?? nil
    }

    private func activeSpaceSnapshot(handle: UnsafeMutableRawPointer) -> WindowServerSnapshot? {
        guard Self.requiredSymbols.allSatisfy({ dlsym(handle, $0) != nil }),
              let mainConnection: MainConnection = loadSymbol(handle, "CGSMainConnectionID"),
              let copyManagedDisplaySpaces: CopyManagedDisplaySpaces = loadSymbol(handle, "CGSCopyManagedDisplaySpaces"),
              let copyWindows: CopyWindows = loadSymbol(handle, "CGSCopyWindowsWithOptionsAndTags"),
              let queryWindows: QueryWindows = loadSymbol(handle, "SLSWindowQueryWindows"),
              let copyQueryWindows: QueryResultCopyWindows = loadSymbol(handle, "SLSWindowQueryResultCopyWindows"),
              let iteratorAdvance: IteratorAdvance = loadSymbol(handle, "SLSWindowIteratorAdvance"),
              let iteratorGetWindowID: IteratorGetWindowID = loadSymbol(handle, "SLSWindowIteratorGetWindowID"),
              let iteratorGetPID: IteratorGetPID = loadSymbol(handle, "SLSWindowIteratorGetPID") else {
            return nil
        }

        let connection = mainConnection()
        guard let displays = copyManagedDisplaySpaces(connection)?.takeRetainedValue() else { return nil }
        guard let managedDisplays = displays as? [[String: Any]] else { return nil }
        let activeSpaceIDs = ManagedDisplaySpaceTopology.currentSpaceIDs(from: managedDisplays)
        guard !activeSpaceIDs.isEmpty else { return nil }

        var setTags = 0
        var clearTags = 0
        guard let rawWindows = copyWindows(
            connection,
            0,
            activeSpaceIDs as CFArray,
            Self.includeInvisibleWindows,
            &setTags,
            &clearTags
        )?.takeRetainedValue() else { return nil }

        var seen: Set<WindowID> = []
        let orderedWIDs = (rawWindows as NSArray).compactMap { value -> WindowID? in
            guard let number = value as? NSNumber else { return nil }
            let wid = number.uint32Value
            return seen.insert(wid).inserted ? wid : nil
        }
        guard !orderedWIDs.isEmpty else {
            return WindowServerSnapshot(activeSpaceIDs: activeSpaceIDs, windows: [])
        }
        guard let query = queryWindows(
            connection,
            orderedWIDs as CFArray,
            Int32(orderedWIDs.count)
        )?.takeRetainedValue(),
              let iterator = copyQueryWindows(query)?.takeRetainedValue() else {
            return nil
        }

        var pidsByWID: [WindowID: ProcessID] = [:]
        while iteratorAdvance(iterator) {
            pidsByWID[iteratorGetWindowID(iterator)] = iteratorGetPID(iterator)
        }
        let windows = orderedWIDs.enumerated().compactMap { order, wid -> WindowServerWindow? in
            guard let pid = pidsByWID[wid], pid > 0 else { return nil }
            return WindowServerWindow(wid: wid, pid: pid, frontToBackOrder: order)
        }
        return WindowServerSnapshot(activeSpaceIDs: activeSpaceIDs, windows: windows)
    }

    private func withLibrary<T>(_ body: (UnsafeMutableRawPointer) -> T) -> T? {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW | RTLD_LOCAL) else { return nil }
        defer { dlclose(handle) }
        return body(handle)
    }

    private func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
