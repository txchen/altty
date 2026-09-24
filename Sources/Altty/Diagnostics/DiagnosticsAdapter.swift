import Foundation
import OSLog

enum DiagnosticEvent: Equatable, Sendable {
    case accessibilityAvailable
    case accessibilityUnavailable
    case skyLightAvailable
    case skyLightUnavailable
}

enum PerformanceAdapter: String, Equatable, Sendable {
    case accessibility
    case skyLight = "skylight"
}

enum PerformanceMetric: String, Equatable, Sendable {
    case shortcutToFocusStart = "shortcut_to_focus_start"
    case shortcutToPanelPresentation = "shortcut_to_panel_presentation"
    case panelPreparation = "panel_preparation"
}

enum PerformanceEvent: Equatable, Sendable {
    case adapterCall(PerformanceAdapter)
    case latency(PerformanceMetric, nanoseconds: UInt64)
}

protocol DiagnosticsAdapter: Sendable {
    func record(_ event: DiagnosticEvent)
    func recordPerformance(_ event: PerformanceEvent)
}

extension DiagnosticsAdapter {
    func recordPerformance(_ event: PerformanceEvent) {}
}

struct UnifiedLogDiagnosticsAdapter: DiagnosticsAdapter {
    private let logger = Logger(subsystem: "app.altty.macos", category: "Readiness")
    private let performanceLogger = Logger(subsystem: "app.altty.macos", category: "Performance")

    func record(_ event: DiagnosticEvent) {
        switch event {
        case .accessibilityAvailable:
            logger.info("permission category=accessibility status=available")
        case .accessibilityUnavailable:
            logger.error("permission category=accessibility status=unavailable")
        case .skyLightAvailable:
            logger.info("capability category=skylight status=available")
        case .skyLightUnavailable:
            logger.error("capability category=skylight status=unavailable")
        }
    }

    func recordPerformance(_ event: PerformanceEvent) {
        switch event {
        case let .adapterCall(adapter):
            performanceLogger.info("adapter_call adapter=\(adapter.rawValue, privacy: .public)")
        case let .latency(metric, nanoseconds):
            performanceLogger.info(
                "latency metric=\(metric.rawValue, privacy: .public) nanoseconds=\(nanoseconds)"
            )
        }
    }
}
