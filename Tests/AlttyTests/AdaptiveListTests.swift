import Foundation
import Testing
@testable import Altty

struct AdaptiveListTests {
    @Test func autoUsesTheLargestSizeThatFitsThenScrollsAtSmall() {
        for (count, size): (Int, ListSize) in [(3, .large), (9, .large), (10, .medium), (11, .small), (24, .small)] {
            let layout = SwitcherListLayout(rowCount: count, preference: .auto,
                                            screenHeight: 900, visibleHeight: 860)
            #expect(layout.size == size)
            #expect(layout.height <= 720)
            if count <= 11 { #expect(layout.visibleRowCapacity >= count) }
            else { #expect(layout.visibleRowCapacity == 12) }
        }
    }

    @Test func manualSizesStayFixedAndRespectTheChosenScreensAvailableHeight() {
        for size in [ListSize.small, .medium, .large] {
            let layout = SwitcherListLayout(rowCount: 100, preference: size,
                                            screenHeight: 1000, visibleHeight: 600)
            #expect(layout.size == size)
            #expect(layout.height <= 600)
            #expect(layout.height == CGFloat(50 + Double(layout.visibleRowCapacity) * (size.rowHeight + 2)))
        }
        let short = SwitcherListLayout(rowCount: 2, preference: .auto,
                                       screenHeight: 1000, visibleHeight: 960)
        #expect(short.height == 190)
        let empty = SwitcherListLayout(rowCount: 0, preference: .auto,
                                       screenHeight: 1000, visibleHeight: 960)
        #expect(empty.height == 120)
    }

    @Test func legacyRowLimitsRetireWithoutLosingSizeOrOtherPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let original = SettingsSnapshot(shortcuts: .defaults, exceptionRules: [], general:
            .init(launchAtLogin: true, listPresentation: .defaults,
                  reverseMouseWheel: true, diagnosticLoggingEnabled: true, hintMode: .disabled))
        try persistence.saveSettings(original)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var general = try #require(json["general"] as? [String: Any])
        json["version"] = 4
        for (density, size): (String, ListSize) in [("compact", .small), ("comfortable", .medium)] {
            general["listPresentation"] = ["visibleRowCount": 7, "density": density]
            json["general"] = general
            try JSONSerialization.data(withJSONObject: json).write(to: url)
            let result = persistence.loadSettings()
            #expect(result.warning == nil)
            #expect(result.snapshot.version == 5)
            #expect(result.snapshot.general.listPresentation.size == size)
            #expect(result.snapshot.general.launchAtLogin)
            #expect(result.snapshot.general.reverseMouseWheel)
            #expect(result.snapshot.general.diagnosticLoggingEnabled)
            #expect(result.snapshot.exceptionRules.isEmpty)
            try persistence.saveSettings(result.snapshot)
            let saved = try String(contentsOf: url, encoding: .utf8)
            #expect(!saved.contains("visibleRowCount"))
            #expect(!saved.contains("density"))
            #expect(persistence.loadSettings().snapshot == result.snapshot)
        }
    }
}
