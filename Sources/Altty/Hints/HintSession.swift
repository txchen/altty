enum HintKey: Equatable, Sendable {
    case letter(Character)
    case backspace
    case escape
    case enter(HintClickModifiers)
    case controlTap
    case hintShortcut
    /// A ⌘, ⌃ or ⌥ chord other than a modifier plus Return.
    case passThroughChord
    case other
}

struct HintPerformance: Equatable, Sendable {
    let action: HintAction
    let target: Int
}

struct HintStep: Equatable, Sendable {
    enum Next: Equatable, Sendable {
        case stay
        case awaitSecondClick
        case end
    }

    let swallow: Bool
    let redraw: Bool
    let perform: HintPerformance?
    let next: Next

    static let ignored = HintStep(swallow: true, redraw: false, perform: nil, next: .stay)
    static let redrawn = HintStep(swallow: true, redraw: true, perform: nil, next: .stay)
    static let cancelled = HintStep(swallow: true, redraw: false, perform: nil, next: .end)
    static let passedThroughAndEnded = HintStep(swallow: false, redraw: false, perform: nil, next: .end)

    static func performing(_ action: HintAction, on target: Int, then next: Next = .end) -> HintStep {
        HintStep(swallow: true, redraw: false, perform: HintPerformance(action: action, target: target), next: next)
    }
}

struct HintBadge: Equatable, Sendable {
    let target: Int
    let label: String
    let typedCount: Int
    let isSelected: Bool
}

/// The keyboard half of a Hint Session over already-ordered targets. Targets
/// are identified by index; labels beyond `HintLabels.capacity` are dropped.
struct HintSession: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case choosing
        case awaitingSecondClick(target: Int)
    }

    let labels: [String]
    private let defaultActions: [HintDefaultAction]
    private(set) var typed = ""
    private(set) var selection: Int?
    private(set) var phase = Phase.choosing

    init(defaultActions: [HintDefaultAction]) {
        labels = HintLabels.make(count: defaultActions.count)
        self.defaultActions = Array(defaultActions.prefix(labels.count))
    }

    var badges: [HintBadge] {
        guard phase == .choosing else { return [] }
        return labels.indices.compactMap { index in
            let label = labels[index]
            let matches = label.hasPrefix(typed)
            guard matches || index == selection else { return nil }
            return HintBadge(
                target: index,
                label: label,
                typedCount: matches ? typed.count : 0,
                isSelected: index == selection
            )
        }
    }

    mutating func handle(_ key: HintKey) -> HintStep {
        switch phase {
        case .choosing: choose(key)
        case let .awaitingSecondClick(target): awaitSecondClick(key, target: target)
        }
    }

    /// The double-click interval ran out; the session ends without acting.
    mutating func doubleClickWindowExpired() -> Bool {
        guard case .awaitingSecondClick = phase else { return false }
        phase = .choosing
        return true
    }

    private mutating func choose(_ key: HintKey) -> HintStep {
        switch key {
        case let .letter(letter):
            let candidate = typed + String(letter)
            if let index = labels.firstIndex(of: candidate) {
                selection = index
                typed = ""
                return .redrawn
            }
            guard labels.contains(where: { $0.hasPrefix(candidate) }) else { return .ignored }
            typed = candidate
            return .redrawn
        case .backspace:
            if !typed.isEmpty {
                typed.removeLast()
                return .redrawn
            }
            guard selection != nil else { return .ignored }
            selection = nil
            return .redrawn
        case let .enter(modifiers):
            guard let target = selection else { return .ignored }
            if modifiers.contains(.control) { return .performing(.rightClick, on: target) }
            if !modifiers.isEmpty { return .performing(.click(modifiers), on: target) }
            guard defaultActions[target] == .click else { return .performing(.defaultAction, on: target) }
            phase = .awaitingSecondClick(target: target)
            return .performing(.defaultAction, on: target, then: .awaitSecondClick)
        case .controlTap:
            guard let target = selection else {
                return HintStep(swallow: false, redraw: false, perform: nil, next: .stay)
            }
            return HintStep(
                swallow: false,
                redraw: false,
                perform: HintPerformance(action: .hover, target: target),
                next: .end
            )
        case .escape, .hintShortcut:
            return .cancelled
        case .passThroughChord:
            return .passedThroughAndEnded
        case .other:
            return .ignored
        }
    }

    private mutating func awaitSecondClick(_ key: HintKey, target: Int) -> HintStep {
        phase = .choosing
        guard key == .enter([]) else { return .passedThroughAndEnded }
        return .performing(.secondClickOfDouble, on: target)
    }
}

/// A Hint Session from the shortcut press on. Keys typed while the scan runs
/// are buffered and replayed in order once targets are known, except keys that
/// end the session, which act immediately.
enum HintCapture: Equatable, Sendable {
    case scanning(buffer: [HintKey])
    case active(HintSession)

    static let started = HintCapture.scanning(buffer: [])

    var session: HintSession? {
        guard case let .active(session) = self else { return nil }
        return session
    }

    mutating func handle(_ key: HintKey) -> HintStep {
        switch self {
        case var .scanning(buffer):
            switch key {
            case .escape, .hintShortcut: return .cancelled
            case .passThroughChord: return .passedThroughAndEnded
            case .controlTap:
                buffer.append(key)
                self = .scanning(buffer: buffer)
                return HintStep(swallow: false, redraw: false, perform: nil, next: .stay)
            case .letter, .backspace, .enter, .other:
                buffer.append(key)
                self = .scanning(buffer: buffer)
                return .ignored
            }
        case var .active(session):
            let step = session.handle(key)
            self = .active(session)
            return step
        }
    }

    /// Replays the buffer, stopping at the first step that ends the session.
    mutating func scanFinished(defaultActions: [HintDefaultAction]) -> [HintStep] {
        guard case let .scanning(buffer) = self else { return [] }
        self = .active(HintSession(defaultActions: defaultActions))
        var steps: [HintStep] = []
        for key in buffer {
            let step = handle(key)
            steps.append(step)
            if step.next == .end { break }
        }
        return steps
    }

    mutating func doubleClickWindowExpired() -> Bool {
        guard case var .active(session) = self else { return false }
        let expired = session.doubleClickWindowExpired()
        self = .active(session)
        return expired
    }
}
