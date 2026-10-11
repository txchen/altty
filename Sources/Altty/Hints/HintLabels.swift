import CoreGraphics

/// Prefix-free, mixed-length labels (Neru's "normal" generator): as many labels
/// as possible stay short, and a prefix is only expanded when the remaining
/// count would not otherwise fit.
enum HintLabels {
    static let alphabet: [Character] = Array("asdfghjkl")
    static let maximumLength = 3

    static func capacity(alphabet: [Character] = alphabet) -> Int {
        (0..<maximumLength).reduce(1) { product, _ in product * alphabet.count }
    }

    static func make(count requested: Int, alphabet: [Character] = alphabet) -> [String] {
        let base = alphabet.count
        guard base > 1 else { return [] }
        let count = min(max(requested, 0), capacity(alphabet: alphabet))
        var labels: [String] = []
        labels.reserveCapacity(count)
        var remaining = count
        var slots = base
        var cursor: [Int] = []
        while remaining > 0 {
            let keep: Int
            if slots >= remaining {
                keep = remaining
            } else if slots * base < remaining {
                keep = 0
            } else {
                keep = (slots * base - remaining) / (base - 1)
            }
            cursor.append(0)
            for _ in 0..<keep {
                labels.append(String(cursor.map { alphabet[$0] }))
                increment(&cursor, base: base)
            }
            remaining -= keep
            slots = (slots - keep) * base
        }
        return labels
    }

    private static func increment(_ cursor: inout [Int], base: Int) {
        for position in cursor.indices.reversed() {
            cursor[position] += 1
            if cursor[position] < base { return }
            cursor[position] = 0
        }
    }

    /// Reading order: top-to-bottom, then left-to-right, on whole points so
    /// sub-point jitter between siblings does not reorder a row.
    static func readingOrder(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let left = (lhs.minY.rounded(), lhs.minX.rounded())
        let right = (rhs.minY.rounded(), rhs.minX.rounded())
        return left < right
    }
}
