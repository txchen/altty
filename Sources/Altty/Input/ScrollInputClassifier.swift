// Adapted from Scroll Reverser, Copyright 2011 Nicholas Moore, Apache-2.0.
// Changes: Swift value-state classifier with an injected monotonic timestamp;
// only mouse reversal is exposed. See Resources/ThirdParty/ScrollReverser.
import Foundation

enum ScrollInputSource: Equatable {
    case mouse
    case trackpad
}

struct ScrollInputClassifier {
    private var touching = 0
    private var lastTouchTime: UInt64 = 0
    private var lastSource: ScrollInputSource = .mouse

    mutating func observeTouches(_ count: Int, at nanoseconds: UInt64) {
        guard count >= 2 else { return }
        touching = max(touching, count)
        lastTouchTime = nanoseconds
    }

    mutating func source(continuous: Bool, momentum: Bool, at nanoseconds: UInt64) -> ScrollInputSource {
        let elapsed = nanoseconds >= lastTouchTime ? nanoseconds - lastTouchTime : 0
        defer { touching = 0 }
        if !continuous {
            lastSource = .mouse
        } else if touching >= 2 && elapsed < 222_000_000 {
            lastSource = .trackpad
        } else if !momentum && elapsed > 333_000_000 {
            lastSource = .mouse
        }
        return lastSource
    }
}
