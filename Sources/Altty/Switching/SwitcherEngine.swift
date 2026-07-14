import Foundation

enum Availability: Equatable, Sendable {
    case unknown
    case unavailable
    case available
}

struct SwitcherPresentationState: Equatable, Sendable {
    private struct DependencyDescription {
        let statusTitle: String
        let detail: String
    }

    let hasLaunched: Bool
    let accessibility: Availability
    let windowServer: Availability

    var isReady: Bool { accessibility == .available && windowServer == .available }

    var readinessTitle: String {
        if isReady { return "Ready" }
        if accessibility == .unavailable { return "Accessibility permission required" }
        if windowServer == .unavailable { return "SkyLight unsupported" }
        return hasLaunched ? "Checking readiness…" : "Starting…"
    }

    private var accessibilityDescription: DependencyDescription {
        switch accessibility {
        case .unknown:
            DependencyDescription(
                statusTitle: "Accessibility: Checking…",
                detail: "Checking whether Altty can read and prepare windows for switching."
            )
        case .unavailable:
            DependencyDescription(
                statusTitle: "Accessibility: Permission Required",
                detail: "Allow Altty in Privacy & Security so it can read and prepare windows for switching."
            )
        case .available:
            DependencyDescription(
                statusTitle: "Accessibility: Ready",
                detail: "Altty has the required Accessibility permission."
            )
        }
    }

    var accessibilityStatusTitle: String { accessibilityDescription.statusTitle }
    var accessibilityDetail: String { accessibilityDescription.detail }

    var showsAccessibilityAction: Bool { accessibility == .unavailable }

    private var skyLightDescription: DependencyDescription {
        switch windowServer {
        case .unknown:
            DependencyDescription(
                statusTitle: "SkyLight: Checking…",
                detail: "Checking the required WindowServer capability."
            )
        case .unavailable:
            DependencyDescription(
                statusTitle: "SkyLight: Unsupported",
                detail: "Required WindowServer capability is unavailable. Altty does not use a public focus fallback."
            )
        case .available:
            DependencyDescription(
                statusTitle: "SkyLight: Ready",
                detail: "The required WindowServer capability is available."
            )
        }
    }

    var skyLightStatusTitle: String { skyLightDescription.statusTitle }
    var skyLightDetail: String { skyLightDescription.detail }
}

enum SwitcherCommand: Equatable, Sendable {
    case launch
    case accessibilityStatusMayHaveChanged
    case systemDidWake
    case openSettings
    case requestAccessibility
    case checkForUpdates
    case quit
    case recheckReadiness
}

enum SwitcherEvent: Equatable, Sendable {
    case accessibilityChanged(Availability)
    case windowServerChanged(Availability)
}

enum SwitcherEffect: Equatable, Sendable {
    case checkAccessibility
    case checkWindowServer
    case setShortcutsEnabled(Bool)
    case endActiveSession
    case releaseAccessibilityObservers
    case recordDiagnostic(DiagnosticEvent)
    case presentSettings
    case requestAccessibility
    case openReleasesPage
    case terminate
}

/// The application-service seam. It owns only value state and requested effects;
/// concrete AppKit and system adapter types remain outside it.
@MainActor
final class SwitcherEngine {
    private(set) var presentationState = SwitcherPresentationState(
        hasLaunched: false,
        accessibility: .unknown,
        windowServer: .unknown
    )

    func send(_ command: SwitcherCommand) -> [SwitcherEffect] {
        switch command {
        case .launch:
            presentationState = SwitcherPresentationState(
                hasLaunched: true,
                accessibility: .unknown,
                windowServer: .unknown
            )
            return [.setShortcutsEnabled(false), .checkAccessibility, .checkWindowServer]
        case .accessibilityStatusMayHaveChanged:
            return [.checkAccessibility]
        case .systemDidWake:
            return beginReadinessCheck()
        case .openSettings:
            return [.presentSettings]
        case .requestAccessibility:
            return [.requestAccessibility, .checkAccessibility]
        case .checkForUpdates:
            return [.openReleasesPage]
        case .quit:
            return [.terminate]
        case .recheckReadiness:
            return beginReadinessCheck()
        }
    }

    private func beginReadinessCheck() -> [SwitcherEffect] {
        presentationState = SwitcherPresentationState(
            hasLaunched: presentationState.hasLaunched,
            accessibility: .unknown,
            windowServer: .unknown
        )
        return [.setShortcutsEnabled(false), .endActiveSession, .checkAccessibility, .checkWindowServer]
    }

    func receive(_ event: SwitcherEvent) -> [SwitcherEffect] {
        let previousState = presentationState
        switch event {
        case let .accessibilityChanged(value):
            presentationState = SwitcherPresentationState(
                hasLaunched: presentationState.hasLaunched,
                accessibility: value,
                windowServer: presentationState.windowServer
            )
        case let .windowServerChanged(value):
            presentationState = SwitcherPresentationState(
                hasLaunched: presentationState.hasLaunched,
                accessibility: presentationState.accessibility,
                windowServer: value
            )
        }
        guard previousState != presentationState else { return [] }

        var effects: [SwitcherEffect] = []
        let accessibilityWasRevoked = previousState.accessibility == .available
            && presentationState.accessibility == .unavailable

        if previousState.isReady && !presentationState.isReady || accessibilityWasRevoked {
            effects.append(.setShortcutsEnabled(false))
            effects.append(.endActiveSession)
            if accessibilityWasRevoked {
                effects.append(.releaseAccessibilityObservers)
            }
        } else if !previousState.isReady && presentationState.isReady {
            effects.append(.setShortcutsEnabled(true))
        }

        switch event {
        case .accessibilityChanged(.available):
            effects.append(.recordDiagnostic(.accessibilityAvailable))
        case .accessibilityChanged(.unavailable):
            effects.append(.recordDiagnostic(.accessibilityUnavailable))
        case .windowServerChanged(.available):
            effects.append(.recordDiagnostic(.skyLightAvailable))
        case .windowServerChanged(.unavailable):
            effects.append(.recordDiagnostic(.skyLightUnavailable))
        case .accessibilityChanged(.unknown), .windowServerChanged(.unknown):
            break
        }
        return effects
    }
}
