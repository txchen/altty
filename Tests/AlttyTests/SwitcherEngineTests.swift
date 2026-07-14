import Testing
@testable import Altty

@MainActor
struct SwitcherEngineTests {
    @Test func launchStartsUnavailableUntilBothDependenciesAreReady() {
        let engine = SwitcherEngine()

        #expect(engine.send(.launch) == [.setShortcutsEnabled(false), .checkAccessibility, .checkWindowServer])
        #expect(engine.presentationState.readinessTitle == "Checking readiness…")
        #expect(engine.receive(.accessibilityChanged(.available)) == [])
        #expect(engine.receive(.windowServerChanged(.available)) == [.setShortcutsEnabled(true)])
        #expect(engine.presentationState.isReady)
        #expect(engine.presentationState.readinessTitle == "Ready")
    }

    @Test func losingReadinessDisablesShortcutsAndExplainsWhy() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.receive(.accessibilityChanged(.unavailable)) == [.setShortcutsEnabled(false)])
        #expect(engine.presentationState.readinessTitle == "Accessibility permission required")
    }

    @Test func menuCommandsExposePresentationEffects() {
        let engine = SwitcherEngine()

        #expect(engine.send(.openSettings) == [.presentSettings])
        #expect(engine.send(.requestAccessibility) == [.requestAccessibility])
        #expect(engine.send(.checkForUpdates) == [.openReleasesPage])
        #expect(engine.send(.quit) == [.terminate])
        #expect(engine.send(.recheckReadiness) == [.setShortcutsEnabled(false), .checkAccessibility, .checkWindowServer])
    }
}
