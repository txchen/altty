import Foundation

struct LatencyDistribution: Codable, Equatable, Sendable {
    let sampleCount: Int
    let p50Nanoseconds: Int64
    let p95Nanoseconds: Int64
    let p99Nanoseconds: Int64

    init(samplesNanoseconds: [Int64]) {
        let sorted = samplesNanoseconds.sorted()
        sampleCount = sorted.count
        p50Nanoseconds = Self.percentile(50, in: sorted)
        p95Nanoseconds = Self.percentile(95, in: sorted)
        p99Nanoseconds = Self.percentile(99, in: sorted)
    }

    private static func percentile(_ percentile: Int, in sorted: [Int64]) -> Int64 {
        guard !sorted.isEmpty else { return 0 }
        let rank = max(1, (percentile * sorted.count + 99) / 100)
        return sorted[min(rank - 1, sorted.count - 1)]
    }

    private enum CodingKeys: String, CodingKey {
        case sampleCount = "sample_count"
        case p50Nanoseconds = "p50_nanoseconds"
        case p95Nanoseconds = "p95_nanoseconds"
        case p99Nanoseconds = "p99_nanoseconds"
    }
}

struct AdapterCallCounts: Codable, Equatable, Sendable {
    let accessibility: Int
    let skyLight: Int

    private enum CodingKeys: String, CodingKey {
        case accessibility
        case skyLight = "skylight"
    }
}

struct PerformanceReport: Codable, Equatable, Sendable {
    let hardwareModel: String
    let osVersion: String
    let buildSHA: String
    let cpuAveragePercent: Double
    let residentMemoryBytes: UInt64
    let wakeups: UInt64
    let adapterCalls: AdapterCallCounts
    let latencies: PerformanceLatencies

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private enum CodingKeys: String, CodingKey {
        case hardwareModel = "hardware_model"
        case osVersion = "os_version"
        case buildSHA = "build_sha"
        case cpuAveragePercent = "cpu_average_percent"
        case residentMemoryBytes = "resident_memory_bytes"
        case wakeups
        case adapterCalls = "adapter_call_counts"
        case latencies
    }
}

struct PerformanceLatencies: Codable, Equatable, Sendable {
    let shortcutToFocusStart: LatencyDistribution
    let shortcutToPanelPresentation: LatencyDistribution
    let filterSortSnapshot100: LatencyDistribution

    private enum CodingKeys: String, CodingKey {
        case shortcutToFocusStart = "shortcut_to_focus_start"
        case shortcutToPanelPresentation = "shortcut_to_panel_presentation"
        case filterSortSnapshot100 = "filter_sort_snapshot_100"
    }
}
