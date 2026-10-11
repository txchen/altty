import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
protocol HintActionPerformer: AnyObject {
    func perform(_ action: HintAction, on target: HintTarget)
}

/// A synthesized pointer gesture at the target's midpoint.
enum HintPointerGesture: Equatable, Sendable {
    case click(HintClickModifiers)
    case rightClick
    case secondClickOfDouble
    case hover

    struct Event: Equatable, Sendable {
        let type: CGEventType
        let button: CGMouseButton
        let flags: CGEventFlags
        let clickState: Int64
    }

    /// Down and up are posted with a short pause between them.
    var events: [Event] {
        switch self {
        case let .click(modifiers):
            let flags = modifiers.eventFlags
            return [
                Event(type: .mouseMoved, button: .left, flags: [], clickState: 0),
                Event(type: .leftMouseDown, button: .left, flags: flags, clickState: 1),
                Event(type: .leftMouseUp, button: .left, flags: flags, clickState: 1),
            ]
        case .rightClick:
            return [
                Event(type: .mouseMoved, button: .left, flags: [], clickState: 0),
                Event(type: .rightMouseDown, button: .right, flags: [], clickState: 1),
                Event(type: .rightMouseUp, button: .right, flags: [], clickState: 1),
            ]
        case .secondClickOfDouble:
            return [
                Event(type: .leftMouseDown, button: .left, flags: [], clickState: 2),
                Event(type: .leftMouseUp, button: .left, flags: [], clickState: 2),
            ]
        case .hover:
            return [Event(type: .mouseMoved, button: .left, flags: [], clickState: 0)]
        }
    }
}

enum HintActionPlan: Equatable, Sendable {
    /// An AX action, falling back to `fallback` if the element refuses it.
    case accessibility(action: String, bringsAppForward: Bool, fallback: HintPointerGesture)
    case pointer(HintPointerGesture)

    init(_ action: HintAction, defaultAction: HintDefaultAction) {
        switch action {
        case .defaultAction:
            switch defaultAction {
            case .press: self = .accessibility(action: kAXPressAction, bringsAppForward: false, fallback: .click([]))
            case .raise: self = .accessibility(action: kAXRaiseAction, bringsAppForward: true, fallback: .click([]))
            case .click: self = .pointer(.click([]))
            }
        case let .click(modifiers): self = .pointer(.click(modifiers))
        case .rightClick: self = .pointer(.rightClick)
        case .secondClickOfDouble: self = .pointer(.secondClickOfDouble)
        case .hover: self = .pointer(.hover)
        }
    }

    /// A timeout may mean the action ran and the app is busy (a modal opened),
    /// so only an outright refusal falls back to a click.
    static func shouldFallBack(after error: AXError) -> Bool {
        error != .success && error != .cannotComplete
    }
}

/// Actions run in order on a serial queue: AX actions are remote IPC, and a
/// double click's second click must follow its first.
@MainActor
final class SystemHintActionPerformer: HintActionPerformer {
    private nonisolated static let actionTimeout: Float = 0.5
    private nonisolated static let pressDuration: TimeInterval = 0.008

    private let queue = DispatchQueue(label: "app.altty.hints.action", qos: .userInteractive)

    func perform(_ action: HintAction, on target: HintTarget) {
        let plan = HintActionPlan(action, defaultAction: target.defaultAction)
        queue.async {
            autoreleasepool { Self.run(plan, on: target) }
        }
    }

    private nonisolated static func run(_ plan: HintActionPlan, on target: HintTarget) {
        switch plan {
        case let .pointer(gesture):
            post(gesture, at: target.midpoint)
        case let .accessibility(action, bringsAppForward, fallback):
            let element = target.element.element
            AXUIElementSetMessagingTimeout(element, actionTimeout)
            let error = AXUIElementPerformAction(element, action as CFString)
            if HintActionPlan.shouldFallBack(after: error) {
                post(fallback, at: target.midpoint)
            } else if bringsAppForward {
                bringForward(owning: element)
            }
        }
    }

    private nonisolated static func bringForward(owning element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, actionTimeout)
        AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private nonisolated static func post(_ gesture: HintPointerGesture, at point: CGPoint) {
        for event in gesture.events {
            guard let posted = CGEvent(
                mouseEventSource: nil,
                mouseType: event.type,
                mouseCursorPosition: point,
                mouseButton: event.button
            ) else { return }
            posted.flags = event.flags
            if event.clickState > 0 {
                posted.setIntegerValueField(.mouseEventClickState, value: event.clickState)
            }
            posted.setIntegerValueField(.eventSourceUserData, value: HintEventMarker.userData)
            posted.post(tap: .cgSessionEventTap)
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                Thread.sleep(forTimeInterval: pressDuration)
            }
        }
    }
}
