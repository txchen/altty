import Foundation

enum Availability: Equatable, Sendable {
    case unknown
    case unavailable
    case available
}

struct SwitcherPresentationState: Equatable, Sendable {
    let hasLaunched: Bool
    let accessibility: Availability
    let windowServer: Availability

    var isReady: Bool { accessibility == .available && windowServer == .available }

    var readinessTitle: String {
        if isReady { return "Ready" }
        if accessibility == .unavailable { return "Accessibility permission required" }
        if windowServer == .unavailable { return "Window switching unavailable" }
        return hasLaunched ? "Checking readiness…" : "Starting…"
    }
}

enum SwitcherCommand: Equatable, Sendable {
    case launch
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
        case .openSettings:
            return [.presentSettings]
        case .requestAccessibility:
            return [.requestAccessibility]
        case .checkForUpdates:
            return [.openReleasesPage]
        case .quit:
            return [.terminate]
        case .recheckReadiness:
            return [.setShortcutsEnabled(false), .checkAccessibility, .checkWindowServer]
        }
    }

    func receive(_ event: SwitcherEvent) -> [SwitcherEffect] {
        let wasReady = presentationState.isReady
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
        guard wasReady != presentationState.isReady else { return [] }
        return [.setShortcutsEnabled(presentationState.isReady)]
    }
}
