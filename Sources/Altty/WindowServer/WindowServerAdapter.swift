import AppKit
import CoreFoundation
import Darwin
import Foundation

private func loadDynamicSymbol<T>(
    _ handle: UnsafeMutableRawPointer,
    _ name: String
) -> T? {
    guard let symbol = dlsym(handle, name) else { return nil }
    return unsafeBitCast(symbol, to: T.self)
}

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
    case destroyed(WindowIdentity)
    case focused(WindowIdentity)
    case semanticsInvalidated(WindowIdentity)
    case activeSpaceChanged
}

@MainActor
protocol WindowServerAdapter: AnyObject {
    func availability() -> Availability
    func activeSpaceSnapshot() async -> WindowServerSnapshot?
    func focus(_ identity: WindowIdentity) async -> Bool
    func startMonitoringActiveSpace(_ onChange: @escaping @MainActor () -> Void)
    func stopMonitoringActiveSpace()
    func startMonitoringInventory(_ onEvent: @escaping @MainActor (WindowServerInventoryEvent) -> Void)
    func stopMonitoringInventory()
    func acceptInventorySnapshot(
        _ snapshot: WindowServerSnapshot,
        generation: InventoryGeneration
    ) -> Bool
}

@MainActor
final class SystemWindowServerAdapter: WindowServerAdapter {
    private var activeSpaceObserver: NSObjectProtocol?
    private var inventoryEventHandler: (@MainActor (WindowServerInventoryEvent) -> Void)?
    private var eventTap: SkyLightEventTap?

    func availability() -> Availability {
        guard let snapshot = SkyLightQuery().activeSpaceSnapshot(),
              installEventTapIfNeeded(),
              eventTap?.subscribe(to: snapshot.windows, generation: 0) == true else {
            return .unavailable
        }
        eventTap?.clearKnownWindows()
        eventTap?.isEnabled = false
        return .available
    }

    func activeSpaceSnapshot() async -> WindowServerSnapshot? {
        let snapshot = await Task.detached(priority: .userInitiated) {
            SkyLightQuery().activeSpaceSnapshot()
        }.value
        return snapshot
    }

    func focus(_ identity: WindowIdentity) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            SkyLightFocus().focus(identity)
        }.value
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
        guard installEventTapIfNeeded() else { return }
        eventTap?.isEnabled = true
    }

    func stopMonitoringInventory() {
        inventoryEventHandler = nil
        eventTap?.isEnabled = false
        eventTap?.clearKnownWindows()
        stopMonitoringActiveSpace()
    }

    func acceptInventorySnapshot(
        _ snapshot: WindowServerSnapshot,
        generation: InventoryGeneration
    ) -> Bool {
        eventTap?.subscribe(to: snapshot.windows, generation: generation) == true
    }

    private func installEventTapIfNeeded() -> Bool {
        if eventTap != nil { return true }
        eventTap = SkyLightEventTap { [weak self] event in
            Task { @MainActor in
                guard let self, let handler = self.inventoryEventHandler else { return }
                handler(event)
            }
        }
        return eventTap != nil
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
    private var identitiesByWindowID: [WindowID: WindowIdentity] = [:]
    private let onEvent: @Sendable (WindowServerInventoryEvent) -> Void

    init(onEvent: @escaping @Sendable (WindowServerInventoryEvent) -> Void) {
        self.onEvent = onEvent
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock { self.enabled = enabled }
    }

    func setKnownWindows(_ windows: [WindowServerWindow], generation: InventoryGeneration) {
        lock.withLock {
            identitiesByWindowID = Dictionary(
                windows.map {
                    ($0.wid, WindowIdentity(wid: $0.wid, pid: $0.pid, generation: generation))
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    func publish(rawEvent: UInt32, wid: WindowID) {
        let state = lock.withLock { (enabled, identitiesByWindowID[wid]) }
        guard state.0, let code = SkyLightEventCode(rawValue: rawEvent) else { return }
        let event: WindowServerInventoryEvent?
        switch code {
        case .windowCreated:
            event = wid == 0 ? nil : .created(wid)
        case .windowDestroyed:
            event = state.1.map(WindowServerInventoryEvent.destroyed)
            _ = lock.withLock { identitiesByWindowID.removeValue(forKey: wid) }
        case .windowFocused:
            event = state.1.map(WindowServerInventoryEvent.focused)
        case .windowMoved, .windowResized, .windowOrderedIn, .windowOrderedOut:
            event = state.1.map(WindowServerInventoryEvent.semanticsInvalidated)
        case .spaceCurrentChanged, .activeSpaceChanged:
            lock.withLock { identitiesByWindowID.removeAll() }
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
              let mainConnection: MainConnection = loadDynamicSymbol(handle, "CGSMainConnectionID"),
              let register: RegisterNotification = loadDynamicSymbol(handle, "SLSRegisterConnectionNotifyProc"),
              let request: RequestNotifications = loadDynamicSymbol(handle, "SLSRequestNotificationsForWindows") else {
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

    func subscribe(
        to windows: [WindowServerWindow],
        generation: InventoryGeneration
    ) -> Bool {
        var unique = Array(Set(windows.map(\.wid))).filter { $0 != 0 }
        guard !unique.isEmpty else {
            context.takeUnretainedValue().setKnownWindows([], generation: generation)
            return true
        }
        guard requestNotifications(connection, &unique, Int32(unique.count)) == 0 else {
            context.takeUnretainedValue().setKnownWindows([], generation: 0)
            return false
        }
        context.takeUnretainedValue().setKnownWindows(windows, generation: generation)
        return true
    }

    func clearKnownWindows() {
        context.takeUnretainedValue().setKnownWindows([], generation: 0)
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

    func activeSpaceSnapshot() -> WindowServerSnapshot? {
        withLibrary { activeSpaceSnapshot(handle: $0) } ?? nil
    }

    private func activeSpaceSnapshot(handle: UnsafeMutableRawPointer) -> WindowServerSnapshot? {
        guard Self.requiredSymbols.allSatisfy({ dlsym(handle, $0) != nil }),
              let mainConnection: MainConnection = loadDynamicSymbol(handle, "CGSMainConnectionID"),
              let copyManagedDisplaySpaces: CopyManagedDisplaySpaces = loadDynamicSymbol(handle, "CGSCopyManagedDisplaySpaces"),
              let copyWindows: CopyWindows = loadDynamicSymbol(handle, "CGSCopyWindowsWithOptionsAndTags"),
              let queryWindows: QueryWindows = loadDynamicSymbol(handle, "SLSWindowQueryWindows"),
              let copyQueryWindows: QueryResultCopyWindows = loadDynamicSymbol(handle, "SLSWindowQueryResultCopyWindows"),
              let iteratorAdvance: IteratorAdvance = loadDynamicSymbol(handle, "SLSWindowIteratorAdvance"),
              let iteratorGetWindowID: IteratorGetWindowID = loadDynamicSymbol(handle, "SLSWindowIteratorGetWindowID"),
              let iteratorGetPID: IteratorGetPID = loadDynamicSymbol(handle, "SLSWindowIteratorGetPID") else {
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

}

private struct SkyLightFocus: Sendable {
    private typealias GetProcessForPIDFunction = @convention(c) (
        ProcessID,
        UnsafeMutablePointer<ProcessSerialNumber>
    ) -> OSStatus
    private typealias SetFrontProcess = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        WindowID,
        UInt32
    ) -> CGError
    private typealias PostEventRecord = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>,
        UnsafeMutablePointer<UInt8>
    ) -> CGError

    private static let userGeneratedFocus: UInt32 = 0x200

    private struct KeyWindowEventRecord {
        private static let bufferSize = 0x100
        private static let recordLengthOffset = 0x04
        private static let recordLength: UInt8 = 0xf8
        private static let eventTypeOffset = 0x08
        private static let leftMouseDown: UInt8 = 0x01
        private static let leftMouseUp: UInt8 = 0x02
        private static let windowLocationOffset = 0x20
        private static let windowIDOffset = 0x3c
        private static let compatibilityFlagOffset = 0x3a
        private static let compatibilityFlag: UInt8 = 0x10

        private var bytes = [UInt8](repeating: 0, count: Self.bufferSize)

        init(wid: WindowID) {
            var wid = wid
            var offContentPoint = CGPoint(x: -1, y: -1)
            bytes[Self.recordLengthOffset] = Self.recordLength
            bytes[Self.compatibilityFlagOffset] = Self.compatibilityFlag
            bytes.withUnsafeMutableBytes { destination in
                withUnsafeBytes(of: &wid) { source in
                    destination.baseAddress?.advanced(by: Self.windowIDOffset)
                        .copyMemory(from: source.baseAddress!, byteCount: source.count)
                }
                withUnsafeBytes(of: &offContentPoint) { source in
                    destination.baseAddress?.advanced(by: Self.windowLocationOffset)
                        .copyMemory(from: source.baseAddress!, byteCount: source.count)
                }
            }
        }

        mutating func post(
            to psn: inout ProcessSerialNumber,
            using postEvent: PostEventRecord
        ) -> Bool {
            bytes[Self.eventTypeOffset] = Self.leftMouseDown
            let down = postEvent(&psn, &bytes)
            bytes[Self.eventTypeOffset] = Self.leftMouseUp
            let up = postEvent(&psn, &bytes)
            return down == .success && up == .success
        }
    }

    func focus(_ identity: WindowIdentity) -> Bool {
        guard identity.wid != 0, identity.pid > 0,
              let processHandle = dlopen(nil, RTLD_NOW | RTLD_LOCAL),
              let skyLightHandle = dlopen(SkyLightQuery.frameworkPath, RTLD_NOW | RTLD_LOCAL) else {
            return false
        }
        defer {
            dlclose(skyLightHandle)
            dlclose(processHandle)
        }
        guard let getProcess: GetProcessForPIDFunction = loadDynamicSymbol(processHandle, "GetProcessForPID"),
              let setFront: SetFrontProcess = loadDynamicSymbol(skyLightHandle, "_SLPSSetFrontProcessWithOptions"),
              let postEvent: PostEventRecord = loadDynamicSymbol(skyLightHandle, "SLPSPostEventRecordTo") else {
            return false
        }

        var psn = ProcessSerialNumber()
        guard getProcess(identity.pid, &psn) == noErr,
              setFront(&psn, identity.wid, Self.userGeneratedFocus) == .success else {
            return false
        }
        var record = KeyWindowEventRecord(wid: identity.wid)
        return record.post(to: &psn, using: postEvent)
    }

}
