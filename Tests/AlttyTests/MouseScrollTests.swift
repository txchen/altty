import AppKit
import Testing
@testable import Altty

struct ScrollInputClassifierTests {
    @Test func discreteWheelsAndContinuousMiceAreBothRecognized() {
        var classifier = ScrollInputClassifier()
        #expect(classifier.source(continuous: false, momentum: false, at: 1_000_000_000) == .mouse)
        #expect(classifier.source(continuous: true, momentum: false, at: 2_000_000_000) == .mouse)
        classifier.observeTouches(2, at: 2_100_000_000)
        #expect(classifier.source(continuous: false, momentum: false, at: 2_110_000_000) == .mouse)
    }

    @Test func multiTouchIdentifiesTrackpadAndMomentumKeepsItsSource() {
        var classifier = ScrollInputClassifier()
        classifier.observeTouches(2, at: 1_000_000_000)
        #expect(classifier.source(continuous: true, momentum: false, at: 1_100_000_000) == .trackpad)
        #expect(classifier.source(continuous: true, momentum: true, at: 3_000_000_000) == .trackpad)
        #expect(classifier.source(continuous: true, momentum: true, at: 5_000_000_000) == .trackpad)
        #expect(classifier.source(continuous: true, momentum: false, at: 5_100_000_000) == .mouse)
    }

    @Test func singleTouchDoesNotMisclassifyMagicMouseAndAmbiguityKeepsPriorSource() {
        var classifier = ScrollInputClassifier()
        classifier.observeTouches(1, at: 1_000_000_000)
        #expect(classifier.source(continuous: true, momentum: false, at: 1_010_000_000) == .mouse)
        classifier.observeTouches(3, at: 2_000_000_000)
        #expect(classifier.source(continuous: true, momentum: false, at: 2_100_000_000) == .trackpad)
        classifier.observeTouches(0, at: 2_200_000_000)
        #expect(classifier.source(continuous: true, momentum: false, at: 2_300_000_000) == .trackpad)
        #expect(classifier.source(continuous: true, momentum: false, at: 2_334_000_000) == .mouse)
    }
}

@MainActor
struct MouseScrollTests {
    private func wheel(continuous: Bool = false) throws -> CGEvent {
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                        wheelCount: 2, wheel1: 3, wheel2: -2, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 3.25)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2.5)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 37)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -29)
        event.flags = [.maskShift, .maskControl]
        event.timestamp = 123_456
        return event
    }

    @Test func bothAxesReverseWithoutLosingFractionalDeltasOrChangingModifiers() throws {
        let event = try wheel()
        MouseWheelReversal.apply(to: event)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 2)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -3.25)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 2.5)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -37)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 29)
        #expect(event.flags == [.maskShift, .maskControl])
        #expect(event.timestamp == 123_456)
        MouseWheelReversal.apply(to: event)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3)
        #expect(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == 3.25)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 37)
    }

    @Test func disabledInputPassesThroughAndContinuousMouseIncludesHIDReversal() throws {
        let tap = TestMouseScrollTap()
        let hid = TestMouseScrollHID()
        let adapter = SystemMouseScrollAdapter(tap: tap, hid: hid, canListen: { true }, now: { 1_000_000_000 })
        let event = try wheel(continuous: true)
        #expect(adapter.setEnabled(true) == .active)
        #expect(adapter.setEnabled(true) == .active)
        #expect(tap.starts == 1)
        tap.emit(.scrollWheel, event)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
        #expect(hid.before == 3)
        #expect(hid.after == -3)
        #expect(adapter.setEnabled(false) == .disabled)
        let original = try wheel()
        tap.emit(.scrollWheel, original) // Stale callbacks must pass through too.
        #expect(original.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3)
        #expect(tap.stops == 1)
    }

    @Test func tapFailureAndMissingPermissionNeverLeavePartialCapture() throws {
        let tap = TestMouseScrollTap()
        let hid = TestMouseScrollHID()
        let denied = SystemMouseScrollAdapter(tap: tap, hid: hid, canListen: { false })
        #expect(denied.setEnabled(true) == .inputMonitoringRequired)
        #expect(tap.starts == 0)
        hid.isAvailable = false
        let adapter = SystemMouseScrollAdapter(tap: tap, hid: hid, canListen: { true })
        #expect(adapter.setEnabled(true) == .unavailable)
        #expect(tap.starts == 0)
        hid.isAvailable = true
        tap.startSucceeds = false
        #expect(adapter.setEnabled(true) == .unavailable)
        #expect(tap.stops == 1)
        let event = try wheel()
        tap.emit(.scrollWheel, event)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3)
    }

    @Test func timedOutTapRecoversButFailedRecoveryPassesThroughAndReportsFailure() throws {
        let tap = TestMouseScrollTap()
        let adapter = SystemMouseScrollAdapter(tap: tap, hid: TestMouseScrollHID(), canListen: { true })
        var statuses: [MouseScrollStatus] = []
        adapter.installStatusHandler { statuses.append($0) }
        #expect(adapter.setEnabled(true) == .active)
        let event = try wheel()
        tap.emit(.tapDisabledByTimeout, event)
        #expect(tap.reenables == 1)
        #expect(statuses.isEmpty)
        tap.reenableSucceeds = false
        tap.emit(.tapDisabledByTimeout, event)
        #expect(statuses == [.unavailable])
        #expect(tap.stops == 1)
        tap.emit(.scrollWheel, event)
        #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3)
    }

    @Test func enablingWaitsForPersistenceAndIsIndependentOfSkyLight() {
        let engine = SwitcherEngine()
        _ = engine.send(.launch)
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.unavailable))
        let settings = GeneralSettings(launchAtLogin: false, listPresentation: .defaults, reverseMouseWheel: true)
        let snapshot = SettingsSnapshot(shortcuts: .defaults, general: settings)
        #expect(engine.send(.replaceGeneralSettings(settings)) == [.persistSettings(snapshot)])
        #expect(engine.receiveSettingsPersistence(.saved(snapshot)) == [.setMouseScrollReversalEnabled(true)])
        engine.receiveMouseScrollStatus(.active)
        #expect(engine.presentationState.generalSettings.current.reverseMouseWheel)
        #expect(engine.presentationState.generalSettings.mouseScrollStatus == .active)
        #expect(!engine.presentationState.isReady)
        #expect(!engine.receive(.windowServerChanged(.available)).contains(.setMouseScrollReversalEnabled(false)))
        #expect(!engine.receive(.windowServerChanged(.unavailable)).contains(.setMouseScrollReversalEnabled(false)))
        #expect(engine.receive(.accessibilityChanged(.unavailable)).contains(.setMouseScrollReversalEnabled(false)))
        #expect(engine.receive(.accessibilityChanged(.available)).contains(.setMouseScrollReversalEnabled(true)))
        #expect(engine.send(.systemDidWake).contains(.setMouseScrollReversalEnabled(false)))
    }

    @Test func saveFailurePreservesOldScrollSettingAndLoginReconciliationDoesNotResetIt() {
        let settings = GeneralSettings(launchAtLogin: false, listPresentation: .defaults, reverseMouseWheel: true)
        let engine = SwitcherEngine()
        _ = engine.send(.replaceGeneralSettings(settings))
        #expect(engine.receiveSettingsPersistence(.failed(.init(shortcuts: .defaults, general: settings))) == [])
        #expect(!engine.presentationState.generalSettings.current.reverseMouseWheel)
        let restored = SwitcherEngine(generalSettings: settings)
        _ = restored.send(.launch)
        #expect(restored.receive(.accessibilityChanged(.available)).contains(.setMouseScrollReversalEnabled(true)))
        let effects = restored.receiveLaunchAtLoginStatus(.enabled)
        let expected = GeneralSettings(launchAtLogin: true, listPresentation: .defaults, reverseMouseWheel: true)
        #expect(effects == [.persistSettings(.init(shortcuts: .defaults, general: expected))])
    }

    @Test func oldSettingsMigrateWithReversalOffAndNewSettingSurvivesRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let general = GeneralSettings(launchAtLogin: true,
            listPresentation: .init(visibleRowCount: 8, density: .comfortable), reverseMouseWheel: true)
        let snapshot = SettingsSnapshot(shortcuts: .defaults, general: general)
        try persistence.saveSettings(snapshot)
        #expect(persistence.loadSettings() == .init(snapshot: snapshot, warning: nil))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["version"] = 3
        var oldGeneral = try #require(json["general"] as? [String: Any])
        oldGeneral.removeValue(forKey: "reverseMouseWheel")
        json["general"] = oldGeneral
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let migrated = persistence.loadSettings()
        #expect(migrated.warning == nil)
        #expect(migrated.snapshot.version == 4)
        #expect(migrated.snapshot.general.launchAtLogin)
        #expect(migrated.snapshot.general.listPresentation == general.listPresentation)
        #expect(!migrated.snapshot.general.reverseMouseWheel)
        json["version"] = 4 // Missing fields are corruption in the new schema, not an implicit migration.
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(persistence.loadSettings().warning == .malformed)
    }
}

@MainActor
private final class TestMouseScrollTap: MouseScrollEventTap {
    var starts = 0
    var stops = 0
    var reenables = 0
    var startSucceeds = true
    var reenableSucceeds = true
    var handler: (@MainActor (CGEventType, CGEvent) -> Void)?
    func start(_ handler: @escaping @MainActor (CGEventType, CGEvent) -> Void) -> Bool {
        starts += 1
        self.handler = handler
        return startSucceeds
    }
    func reenable() -> Bool { reenables += 1; return reenableSucceeds }
    func stop() { stops += 1 }
    func emit(_ type: CGEventType, _ event: CGEvent) { handler?(type, event) }
}

@MainActor
private final class TestMouseScrollHID: MouseScrollHIDAccess {
    var isAvailable = true
    var before: Int64?
    var after: Int64?
    func prepareReversal(for event: CGEvent) -> (() -> Void)? {
        before = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        return { self.after = event.getIntegerValueField(.scrollWheelEventDeltaAxis1) }
    }
}
