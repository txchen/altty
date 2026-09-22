// Scroll Reverser compatibility path, adapted for runtime-resolved Swift calls.
// Copyright 2011 Nicholas Moore, Apache-2.0. Attribution and changes are recorded
// in Resources/ThirdParty/ScrollReverser/NOTICE.
import CoreGraphics
import Darwin
import Foundation

private final class ScrollHIDLibraries: @unchecked Sendable {
    let handles: [UnsafeMutableRawPointer]
    init() {
        let paths: [String] = [
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/Frameworks/IOKit.framework/IOKit",
        ]
        handles = paths.compactMap { dlopen($0, RTLD_NOW | RTLD_LOCAL) }
    }
    deinit { handles.forEach { dlclose($0) } }
}

@MainActor
protocol MouseScrollHIDAccess: AnyObject {
    var isAvailable: Bool { get }
    // Capture before CG setters modify related fields; apply after them.
    func prepareReversal(for event: CGEvent) -> (() -> Void)?
}

@MainActor
final class SystemMouseScrollHIDAccess: MouseScrollHIDAccess {
    private typealias CopyEvent = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    private typealias GetFloat = @convention(c) (CFTypeRef, UInt32) -> Double
    private typealias SetFloat = @convention(c) (CFTypeRef, UInt32, Double) -> Void
    private let libraries: ScrollHIDLibraries
    private let copyEvent: CopyEvent?
    private let getFloat: GetFloat?
    private let setFloat: SetFloat?

    init() {
        let libraries = ScrollHIDLibraries()
        self.libraries = libraries
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            for handle in libraries.handles {
                if let pointer = dlsym(handle, name) { return unsafeBitCast(pointer, to: type) }
            }
            return nil
        }
        copyEvent = symbol("CGEventCopyIOHIDEvent", as: CopyEvent.self)
        getFloat = symbol("IOHIDEventGetFloatValue", as: GetFloat.self)
        setFloat = symbol("IOHIDEventSetFloatValue", as: SetFloat.self)
    }

    var isAvailable: Bool { copyEvent != nil && getFloat != nil && setFloat != nil }

    func prepareReversal(for event: CGEvent) -> (() -> Void)? {
        guard let copyEvent, let getFloat, let setFloat,
              let hid = copyEvent(event)?.takeRetainedValue() else { return nil }
        let scrollX: UInt32 = 6 << 16
        let scrollY = scrollX | 1
        let x = getFloat(hid, scrollX)
        let y = getFloat(hid, scrollY)
        return { [libraries] in
            withExtendedLifetime(libraries) {
                setFloat(hid, scrollX, -x)
                setFloat(hid, scrollY, -y)
            }
        }
    }
}
