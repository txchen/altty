import Testing
import Darwin
@testable import Altty

@MainActor
struct SwitcherEngineTests {
    @Test func launchStartsUnavailableUntilBothDependenciesAreReady() {
        let engine = SwitcherEngine()

        #expect(engine.send(.launch) == [.setShortcutsEnabled(false), .checkAccessibility, .checkWindowServer])
        #expect(engine.presentationState.readinessTitle == "Checking readiness…")
        #expect(engine.receive(.accessibilityChanged(.available)) == [.recordDiagnostic(.accessibilityAvailable)])
        #expect(engine.receive(.windowServerChanged(.available)) == [
            .setShortcutsEnabled(true),
            .recordDiagnostic(.skyLightAvailable),
        ])
        #expect(engine.presentationState.isReady)
        #expect(engine.presentationState.readinessTitle == "Ready")
    }

    @Test func losingReadinessDisablesShortcutsAndExplainsWhy() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.receive(.accessibilityChanged(.unavailable)) == [
            .setShortcutsEnabled(false),
            .endActiveSession,
            .releaseAccessibilityObservers,
            .recordDiagnostic(.accessibilityUnavailable),
        ])
        #expect(engine.presentationState.readinessTitle == "Accessibility permission required")
    }

    @Test func menuCommandsExposePresentationEffects() {
        let engine = SwitcherEngine()

        #expect(engine.send(.openSettings) == [.presentSettings])
        #expect(engine.send(.requestAccessibility) == [.requestAccessibility, .checkAccessibility])
        #expect(engine.send(.checkForUpdates) == [.openReleasesPage])
        #expect(engine.send(.quit) == [.terminate])
        #expect(engine.send(.recheckReadiness) == [
            .setShortcutsEnabled(false),
            .endActiveSession,
            .checkAccessibility,
            .checkWindowServer,
        ])
    }

    @Test func accessibilityDenialNeverPromptsWithoutAnExplicitRequest() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.unavailable))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.send(.accessibilityStatusMayHaveChanged) == [.checkAccessibility])
        #expect(engine.send(.requestAccessibility) == [.requestAccessibility, .checkAccessibility])
    }

    @Test func runtimeAccessibilityRevocationFailsClosedAndReleasesResources() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.receive(.accessibilityChanged(.unavailable)) == [
            .setShortcutsEnabled(false),
            .endActiveSession,
            .releaseAccessibilityObservers,
            .recordDiagnostic(.accessibilityUnavailable),
        ])
        #expect(!engine.presentationState.isReady)
    }

    @Test func skyLightFailureRetriesOnlyForWakeOrUserRecheck() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.unavailable))

        #expect(engine.presentationState.readinessTitle == "SkyLight unsupported")
        #expect(engine.send(.accessibilityStatusMayHaveChanged) == [.checkAccessibility])
        #expect(engine.send(.systemDidWake) == [
            .setShortcutsEnabled(false),
            .endActiveSession,
            .checkAccessibility,
            .checkWindowServer,
        ])
        #expect(engine.presentationState.windowServer == .unknown)
    }

    @Test func permissionAndCapabilityCanRecoverWithoutRestarting() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.unavailable))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.send(.accessibilityStatusMayHaveChanged) == [.checkAccessibility])
        #expect(engine.receive(.accessibilityChanged(.available)) == [
            .setShortcutsEnabled(true),
            .recordDiagnostic(.accessibilityAvailable),
        ])

        _ = engine.receive(.windowServerChanged(.unavailable))
        _ = engine.send(.recheckReadiness)
        _ = engine.receive(.accessibilityChanged(.available))
        #expect(engine.receive(.windowServerChanged(.available)) == [
            .setShortcutsEnabled(true),
            .recordDiagnostic(.skyLightAvailable),
        ])
        #expect(engine.presentationState.isReady)
    }

    @Test func presentationDistinguishesPermissionCapabilityAndReadyStates() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.unavailable))
        _ = engine.receive(.windowServerChanged(.available))

        #expect(engine.presentationState.accessibilityStatusTitle == "Accessibility: Permission Required")
        #expect(engine.presentationState.showsAccessibilityAction)
        #expect(engine.presentationState.skyLightStatusTitle == "SkyLight: Ready")

        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.unavailable))
        #expect(engine.presentationState.accessibilityStatusTitle == "Accessibility: Ready")
        #expect(!engine.presentationState.showsAccessibilityAction)
        #expect(engine.presentationState.skyLightStatusTitle == "SkyLight: Unsupported")
        #expect(engine.presentationState.skyLightDetail == "Required WindowServer capability is unavailable. Altty does not use a public focus fallback.")
    }
}

@MainActor
struct WindowServerSmokeTests {
    @Test func realReadOnlySkyLightCapabilityCheck() {
        guard getenv("ALTTY_RUN_SKYLIGHT_SMOKE").map({ String(cString: $0) }) == "1" else { return }

        #expect(SystemWindowServerAdapter().availability() == .available)
    }
}
