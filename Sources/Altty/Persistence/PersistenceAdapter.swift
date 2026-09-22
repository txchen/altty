import Foundation

struct FileSettingsPersistenceAdapter: PersistenceAdapter {
    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    private struct VersionOneSettings: Decodable {
        let shortcuts: ShortcutPair
    }

    private struct LossyExceptionRule: Decodable {
        let value: ExceptionRule?

        init(from decoder: any Decoder) throws {
            value = try? ExceptionRule(from: decoder)
        }
    }

    private struct VersionTwoSettings: Decodable {
        let shortcuts: ShortcutPair
        let exceptionRules: [LossyExceptionRule]
    }

    private struct VersionThreeSettings: Decodable {
        struct General: Decodable {
            let launchAtLogin: Bool
            let listPresentation: ListPresentationPreferences
        }

        let shortcuts: ShortcutPair
        let exceptionRules: [LossyExceptionRule]
        let general: General
    }

    private struct VersionFourSettings: Decodable {
        let shortcuts: ShortcutPair
        let exceptionRules: [LossyExceptionRule]
        let general: GeneralSettings
    }

    let settingsURL: URL

    var diagnosticSettingsURL: URL {
        settingsURL.appendingPathExtension("invalid")
    }

    var diagnosticSettingsURLs: [URL] {
        let directory = settingsURL.deletingLastPathComponent()
        let baseName = diagnosticSettingsURL.lastPathComponent
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { url in
                url.lastPathComponent == baseName
                    || url.lastPathComponent.hasPrefix("\(baseName).")
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare(
                $1.lastPathComponent
            ) == .orderedAscending }
    }

    init(settingsURL: URL = Self.productionSettingsURL) {
        self.settingsURL = settingsURL
    }

    func loadSettings() -> SettingsLoadResult {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return SettingsLoadResult(snapshot: .defaults, warning: nil)
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            let decoder = JSONDecoder()
            let version = try decoder.decode(VersionEnvelope.self, from: data).version
            guard (1...SettingsSnapshot.currentVersion).contains(version) else {
                preserveSettingsForDiagnosis()
                return SettingsLoadResult(
                    snapshot: .defaults,
                    warning: .unsupportedVersion(version)
                )
            }

            let current: VersionFourSettings
            switch version {
            case 1:
                let settings = try decoder.decode(VersionOneSettings.self, from: data)
                current = migrateToVersionFour(migrateToVersionThree(migrateToVersionTwo(settings)))
            case 2:
                current = migrateToVersionFour(migrateToVersionThree(
                    try decoder.decode(VersionTwoSettings.self, from: data)
                ))
            case 3:
                current = migrateToVersionFour(
                    try decoder.decode(VersionThreeSettings.self, from: data)
                )
            default:
                current = try decoder.decode(VersionFourSettings.self, from: data)
            }

            guard current.shortcuts.validationError == nil else {
                preserveSettingsForDiagnosis()
                return SettingsLoadResult(snapshot: .defaults, warning: .invalidShortcuts)
            }
            guard current.general.isValid else {
                preserveSettingsForDiagnosis()
                return SettingsLoadResult(snapshot: .defaults, warning: .invalidGeneralSettings)
            }
            var rules: [ExceptionRule] = []
            var discardedCount = 0
            for decoded in current.exceptionRules {
                guard let rule = decoded.value else {
                    discardedCount += 1
                    continue
                }
                if let index = rules.firstIndex(where: { $0.identity == rule.identity }) {
                    rules[index] = rule
                    discardedCount += 1
                } else {
                    rules.append(rule)
                }
            }
            return SettingsLoadResult(
                snapshot: SettingsSnapshot(
                    shortcuts: current.shortcuts,
                    exceptionRules: rules,
                    general: current.general
                ),
                warning: discardedCount == 0
                    ? nil
                    : .invalidExceptionRules(discardedCount: discardedCount)
            )
        } catch {
            preserveSettingsForDiagnosis()
            return SettingsLoadResult(snapshot: .defaults, warning: .malformed)
        }
    }

    func saveSettings(_ snapshot: SettingsSnapshot) throws {
        guard snapshot.version == SettingsSnapshot.currentVersion,
              snapshot.isValid else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: settingsURL, options: .atomic)
    }

    private func migrateToVersionTwo(
        _ settings: VersionOneSettings
    ) -> VersionTwoSettings {
        VersionTwoSettings(shortcuts: settings.shortcuts, exceptionRules: [])
    }

    private func migrateToVersionThree(
        _ settings: VersionTwoSettings
    ) -> VersionThreeSettings {
        VersionThreeSettings(
            shortcuts: settings.shortcuts,
            exceptionRules: settings.exceptionRules,
            general: .init(launchAtLogin: false, listPresentation: .defaults)
        )
    }

    private func migrateToVersionFour(_ settings: VersionThreeSettings) -> VersionFourSettings {
        VersionFourSettings(
            shortcuts: settings.shortcuts,
            exceptionRules: settings.exceptionRules,
            general: GeneralSettings(
                launchAtLogin: settings.general.launchAtLogin,
                listPresentation: settings.general.listPresentation,
                reverseMouseWheel: false
            )
        )
    }

    private func preserveSettingsForDiagnosis() {
        guard let invalidData = try? Data(contentsOf: settingsURL),
              !diagnosticSettingsURLs.contains(where: {
                  (try? Data(contentsOf: $0)) == invalidData
              }) else { return }
        let existing = diagnosticSettingsURLs
        let destination = existing.isEmpty
            ? diagnosticSettingsURL
            : diagnosticSettingsURL.appendingPathExtension(String(existing.count + 1))
        try? FileManager.default.copyItem(
            at: settingsURL,
            to: destination
        )
    }

    private static var productionSettingsURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appending(path: "app.altty.macos", directoryHint: .isDirectory)
            .appending(path: "settings.json")
    }
}
