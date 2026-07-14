import CoreFoundation
import Darwin
import Foundation

@MainActor
protocol WindowServerAdapter: AnyObject { func availability() -> Availability }

@MainActor
final class SystemWindowServerAdapter: WindowServerAdapter {
    func availability() -> Availability {
        SkyLightCapabilityProbe().isAvailable ? .available : .unavailable
    }
}

private struct SkyLightCapabilityProbe {
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

    private static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let queryOptions = 0
    private static let queryTagMask = 0b111
    private static let requiredWindowTags = 1
    private static let excludedWindowTags = 0
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
    ]

    var isAvailable: Bool {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW | RTLD_LOCAL) else { return false }
        defer { dlclose(handle) }

        guard Self.requiredSymbols.allSatisfy({ dlsym(handle, $0) != nil }),
              let mainConnection: MainConnection = loadSymbol(handle, "CGSMainConnectionID"),
              let copyManagedDisplaySpaces: CopyManagedDisplaySpaces = loadSymbol(handle, "CGSCopyManagedDisplaySpaces"),
              let copyWindows: CopyWindows = loadSymbol(handle, "CGSCopyWindowsWithOptionsAndTags") else {
            return false
        }

        let connection = mainConnection()
        guard let displays = copyManagedDisplaySpaces(connection)?.takeRetainedValue() else { return false }
        let spaceIDs = managedSpaceIDs(from: displays)
        guard !spaceIDs.isEmpty else { return false }

        var requiredTags = Self.requiredWindowTags
        var excludedTags = Self.excludedWindowTags
        guard let windows = copyWindows(
            connection,
            Self.queryOptions,
            spaceIDs as CFArray,
            Self.queryTagMask,
            &requiredTags,
            &excludedTags
        )?.takeRetainedValue() else { return false }
        _ = windows
        return true
    }

    private func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private func managedSpaceIDs(from displays: CFArray) -> [UInt64] {
        (displays as NSArray).flatMap { display -> [UInt64] in
            guard let display = display as? NSDictionary,
                  let spaces = display["Spaces"] as? NSArray else { return [] }
            return spaces.compactMap { space in
                guard let space = space as? NSDictionary else { return nil }
                if let id = space["id64"] as? NSNumber { return id.uint64Value }
                if let id = space["ManagedSpaceID"] as? NSNumber { return id.uint64Value }
                return nil
            }
        }
    }
}
