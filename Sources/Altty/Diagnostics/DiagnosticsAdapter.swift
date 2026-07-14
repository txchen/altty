import Foundation
import OSLog

enum DiagnosticEvent: Equatable, Sendable {
    case accessibilityAvailable
    case accessibilityUnavailable
    case skyLightAvailable
    case skyLightUnavailable
}

protocol DiagnosticsAdapter: Sendable { func record(_ event: DiagnosticEvent) }

struct UnifiedLogDiagnosticsAdapter: DiagnosticsAdapter {
    private let logger = Logger(subsystem: "app.altty.macos", category: "Readiness")

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
}
