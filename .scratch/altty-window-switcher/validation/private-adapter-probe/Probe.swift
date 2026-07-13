import ApplicationServices
import CoreFoundation
import CoreGraphics
import Darwin
import Foundation

typealias CGSConnectionID = UInt32
typealias MainConnection = @convention(c) () -> CGSConnectionID
typealias CopyManagedDisplaySpaces = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>
typealias CopyWindows = @convention(c) (
    CGSConnectionID,
    Int,
    CFArray,
    Int,
    UnsafeMutablePointer<Int>,
    UnsafeMutablePointer<Int>
) -> Unmanaged<CFArray>

private let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
private let requiredSymbols = [
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

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("probe error: \(message)\n".utf8))
    exit(1)
}

private func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as: T.Type) -> T {
    guard let pointer = dlsym(handle, name) else { fail("missing symbol \(name)") }
    return unsafeBitCast(pointer, to: T.self)
}

private func spaceIDs(from displays: CFArray) -> [UInt64] {
    let values = displays as NSArray
    return values.flatMap { display -> [UInt64] in
        guard let dictionary = display as? NSDictionary,
              let spaces = dictionary["Spaces"] as? NSArray else { return [] }
        return spaces.compactMap { space in
            guard let dictionary = space as? NSDictionary else { return nil }
            if let value = dictionary["id64"] as? NSNumber { return value.uint64Value }
            if let value = dictionary["ManagedSpaceID"] as? NSNumber { return value.uint64Value }
            return nil
        }
    }
}

guard let handle = dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) else {
    fail(String(cString: dlerror()))
}
defer { dlclose(handle) }

let symbolAvailability = Dictionary(uniqueKeysWithValues: requiredSymbols.map { ($0, dlsym(handle, $0) != nil) })
guard symbolAvailability.values.allSatisfy({ $0 }) else {
    let missing = symbolAvailability.filter { !$0.value }.keys.sorted().joined(separator: ", ")
    fail("required symbols unavailable: \(missing)")
}

let mainConnection = loadSymbol(handle, "CGSMainConnectionID", as: MainConnection.self)
let copyManagedDisplaySpaces = loadSymbol(handle, "CGSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpaces.self)
let copyWindows = loadSymbol(handle, "CGSCopyWindowsWithOptionsAndTags", as: CopyWindows.self)
let connection = mainConnection()
let displays = copyManagedDisplaySpaces(connection).takeRetainedValue()
let ids = spaceIDs(from: displays)
guard !ids.isEmpty else { fail("managed Space query returned no Space IDs") }

var setTags = 1
var clearTags = 0
let windows = copyWindows(connection, 0, ids as CFArray, 0b111, &setTags, &clearTags).takeRetainedValue()
let publicWindows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

let result: [String: Any] = [
    "accessibilityTrusted": AXIsProcessTrusted(),
    "architecture": ProcessInfo.processInfo.machineArchitecture,
    "connection": connection,
    "displayCount": CFArrayGetCount(displays),
    "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
    "privateWindowCount": CFArrayGetCount(windows),
    "publicWindowCount": publicWindows.count,
    "readOnlyProbe": true,
    "spaceCount": ids.count,
    "symbols": symbolAvailability,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))

private extension ProcessInfo {
    var machineArchitecture: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
