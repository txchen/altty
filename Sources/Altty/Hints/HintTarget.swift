import ApplicationServices
import CoreGraphics

enum HintDefaultAction: Equatable, Sendable {
    case press
    case raise
    case click

    private static let byRole: [String: HintDefaultAction] = [
        "AXButton": .press,
        "AXMenuItem": .press,
        "AXMenuBarItem": .press,
        "AXWindow": .raise,
    ]

    init(role: String) {
        self = Self.byRole[role] ?? .click
    }
}

/// A clickable element found by a scan. `frame` is in AX global coordinates:
/// origin at the primary display's top-left corner, y growing downwards.
struct HintTarget: Sendable {
    let element: AXElementBox
    let frame: CGRect
    let role: String
    let subrole: String?
    let defaultAction: HintDefaultAction

    init(element: AXElementBox, frame: CGRect, role: String, subrole: String?) {
        self.element = element
        self.frame = frame
        self.role = role
        self.subrole = subrole
        defaultAction = HintDefaultAction(role: role)
    }

    var midpoint: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

struct HintClickModifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let command = HintClickModifiers(rawValue: 1 << 0)
    static let shift = HintClickModifiers(rawValue: 1 << 1)
    static let option = HintClickModifiers(rawValue: 1 << 2)
    static let control = HintClickModifiers(rawValue: 1 << 3)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(eventFlags: CGEventFlags) {
        var value: HintClickModifiers = []
        if eventFlags.contains(.maskCommand) { value.insert(.command) }
        if eventFlags.contains(.maskShift) { value.insert(.shift) }
        if eventFlags.contains(.maskAlternate) { value.insert(.option) }
        if eventFlags.contains(.maskControl) { value.insert(.control) }
        self = value
    }

    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        return flags
    }
}

enum HintAction: Equatable, Sendable {
    case defaultAction
    case click(HintClickModifiers)
    case rightClick
    case secondClickOfDouble
    case hover
}

/// Marks events Altty posts so its own taps let them through untouched.
enum HintEventMarker {
    static let userData: Int64 = 0x416C_7474_4869_6E74
}
