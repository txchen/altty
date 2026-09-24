import Foundation
import OSLog

/// Shared by the main-thread adapters and the passive keyboard observer.
final class DiagnosticLogging: @unchecked Sendable {
    static let shared = DiagnosticLogging()
    private let lock = NSLock()
    private var enabled = false

    var isEnabled: Bool { lock.withLock { enabled } }
    func setEnabled(_ enabled: Bool) { lock.withLock { self.enabled = enabled } }

    func record(_ message: @autoclosure () -> String, to logger: Logger) {
        guard isEnabled else { return }
        let value = message()
        logger.info("\(value, privacy: .public)")
    }
}

/// Only shortcut and transaction metadata; never window titles or typed text.
enum ShortcutDiagnostics {
    private static let logger = Logger(subsystem: "app.altty.macos", category: "Shortcut")
    static func record(_ message: @autoclosure () -> String) {
        DiagnosticLogging.shared.record(message(), to: logger)
    }
}

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
            DiagnosticLogging.shared.record("permission category=accessibility status=available", to: logger)
        case .accessibilityUnavailable:
            logger.error("permission category=accessibility status=unavailable")
        case .skyLightAvailable:
            DiagnosticLogging.shared.record("capability category=skylight status=available", to: logger)
        case .skyLightUnavailable:
            logger.error("capability category=skylight status=unavailable")
        }
    }

    func recordPerformance(_ event: PerformanceEvent) {
        guard DiagnosticLogging.shared.isEnabled else { return }
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
