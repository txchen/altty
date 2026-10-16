import Carbon.HIToolbox
import CoreGraphics

enum MouseKey {
    static let up = UInt16(kVK_ANSI_W)
    static let down = UInt16(kVK_ANSI_S)
    static let left = UInt16(kVK_ANSI_A)
    static let right = UInt16(kVK_ANSI_D)
    static let slow = UInt16(kVK_ANSI_U)
    static let fast = UInt16(kVK_ANSI_I)
    static let leftClick = UInt16(kVK_ANSI_J)
    static let rightClick = UInt16(kVK_ANSI_K)
    static let hints = UInt16(kVK_ANSI_F)
}

struct MouseMovement: Equatable {
    var held: Set<UInt16> = []
    var speed: MouseSpeed { held.contains(MouseKey.slow) ? .slow : held.contains(MouseKey.fast) ? .fast : .normal }
    var direction: CGVector {
        let x = Double(held.contains(MouseKey.right) ? 1 : 0) - Double(held.contains(MouseKey.left) ? 1 : 0)
        let y = Double(held.contains(MouseKey.down) ? 1 : 0) - Double(held.contains(MouseKey.up) ? 1 : 0)
        let length = max(1, hypot(x, y))
        return CGVector(dx: x / length, dy: y / length)
    }
    static let controls: Set<UInt16> = [
        MouseKey.left, MouseKey.down, MouseKey.right, MouseKey.up, MouseKey.slow, MouseKey.fast,
    ]
}

enum MouseSpeed: String, Equatable {
    case slow, normal, fast
    var pointsPerSecond: Double {
        switch self {
        case .slow: 120
        case .normal: 600
        case .fast: 1500
        }
    }
}

struct MouseHintPicker {
    let labels: [String]
    private(set) var prefix = ""
    init(count: Int) { labels = HintLabels.make(count: count) }
    mutating func handle(_ key: HintKey) -> Int? {
        switch key {
        case .letter(let letter):
            let next = prefix + String(letter)
            if labels.contains(where: { $0.hasPrefix(next) }) { prefix = next }
        case .backspace:
            if !prefix.isEmpty { prefix.removeLast() }
        default: break
        }
        return labels.firstIndex(of: prefix)
    }
    var badges: [HintBadge] {
        labels.enumerated().compactMap { index, label in
            guard label.hasPrefix(prefix) else { return nil }
            return HintBadge(target: index, label: label, typedCount: prefix.count, isSelected: false)
        }
    }
}

enum MouseScreenGeometry {
    static func project(_ point: CGPoint, onto screens: [CGRect]) -> CGPoint {
        screens.map { frame in
            CGPoint(
                x: min(max(point.x, frame.minX), frame.maxX - 1),
                y: min(max(point.y, frame.minY), frame.maxY - 1))
        }.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) } ?? point
    }
}
