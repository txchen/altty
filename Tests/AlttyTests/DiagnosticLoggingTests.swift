import Foundation
import OSLog
import Testing
@testable import Altty

struct DiagnosticLoggingTests {
    @Test func disabledLoggingSkipsMessageConstructionAndCanBeToggled() {
        let logging = DiagnosticLogging()
        let logger = Logger(subsystem: "app.altty.tests", category: "Diagnostics")
        var evaluations = 0
        func message() -> String { evaluations += 1; return "test diagnostic" }
        logging.record(message(), to: logger)
        #expect(evaluations == 0)
        logging.setEnabled(true)
        logging.record(message(), to: logger)
        #expect(evaluations == 1)
        logging.setEnabled(false)
        logging.record(message(), to: logger)
        #expect(evaluations == 1)
    }

    @Test func oldSettingsDefaultToDisabledAndNewPreferenceSurvivesDiskRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let general = GeneralSettings(launchAtLogin: true, listPresentation: .defaults,
                                      reverseMouseWheel: true, diagnosticLoggingEnabled: true)
        let snapshot = SettingsSnapshot(shortcuts: .defaults, exceptionRules: [], general: general)
        try persistence.saveSettings(snapshot)
        #expect(persistence.loadSettings().snapshot == snapshot)
        var old = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var oldGeneral = try #require(old["general"] as? [String: Any])
        oldGeneral.removeValue(forKey: "diagnosticLoggingEnabled")
        old["general"] = oldGeneral
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        let migrated = persistence.loadSettings()
        #expect(migrated.warning == nil)
        #expect(!migrated.snapshot.general.diagnosticLoggingEnabled)
        #expect(migrated.snapshot.general.reverseMouseWheel)
        #expect(migrated.snapshot.general.launchAtLogin)
        #expect(migrated.snapshot.exceptionRules.isEmpty)
    }
}
