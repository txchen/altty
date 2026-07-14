import Foundation

enum ListDensity: String, Codable, CaseIterable, Equatable, Sendable {
    case compact
    case comfortable

    var title: String {
        switch self {
        case .compact: "Compact"
        case .comfortable: "Comfortable"
        }
    }
}

struct ListPresentationPreferences: Codable, Equatable, Sendable {
    static let defaults = ListPresentationPreferences(
        visibleRowCount: 7,
        density: .compact
    )

    let visibleRowCount: Int
    let density: ListDensity

    var isValid: Bool { (6...8).contains(visibleRowCount) }
}

struct GeneralSettings: Codable, Equatable, Sendable {
    static let defaults = GeneralSettings(
        launchAtLogin: false,
        listPresentation: .defaults
    )

    let launchAtLogin: Bool
    let listPresentation: ListPresentationPreferences

    var isValid: Bool { listPresentation.isValid }
}

struct GeneralSettingsState: Equatable, Sendable {
    var current: GeneralSettings
    var pending: GeneralSettings?
    var error: String?
    var recoveryWarning: String?

    var displayed: GeneralSettings { pending ?? current }
    var inlineMessage: String? { error ?? recoveryWarning }
}

struct SettingsSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 3
    static let defaults = SettingsSnapshot(
        shortcuts: .defaults,
        exceptionRules: [],
        general: .defaults
    )

    let version: Int
    let shortcuts: ShortcutPair
    let exceptionRules: [ExceptionRule]
    let general: GeneralSettings

    init(
        version: Int = currentVersion,
        shortcuts: ShortcutPair,
        exceptionRules: [ExceptionRule] = [],
        general: GeneralSettings = .defaults
    ) {
        self.version = version
        self.shortcuts = shortcuts
        self.exceptionRules = exceptionRules
        self.general = general
    }

    var isValid: Bool {
        shortcuts.validationError == nil
            && Set(exceptionRules.map(\.identity)).count == exceptionRules.count
            && general.isValid
    }
}

enum SettingsLoadWarning: Equatable, Sendable {
    case malformed
    case unsupportedVersion(Int)
    case invalidShortcuts
    case invalidExceptionRules(discardedCount: Int)
    case invalidGeneralSettings

    var message: String {
        switch self {
        case .malformed:
            "Settings could not be read. Safe shortcut defaults are active; the original file was preserved."
        case let .unsupportedVersion(version):
            "Settings version \(version) is not supported. Safe shortcut defaults are active; the original file was preserved."
        case .invalidShortcuts:
            "Saved shortcuts were invalid. Safe defaults are active; the original file was preserved."
        case let .invalidExceptionRules(discardedCount):
            "Skipped \(discardedCount) invalid Exception rule\(discardedCount == 1 ? "" : "s"); valid rules remain active."
        case .invalidGeneralSettings:
            "Saved General settings were invalid. Safe defaults are active; the original file was preserved."
        }
    }
}

struct SettingsLoadResult: Equatable, Sendable {
    let snapshot: SettingsSnapshot
    let warning: SettingsLoadWarning?
}

enum SettingsPersistenceEvent: Equatable, Sendable {
    case saved(SettingsSnapshot)
    case failed(SettingsSnapshot)
}

protocol PersistenceAdapter: Sendable {
    func loadSettings() -> SettingsLoadResult
    func saveSettings(_ snapshot: SettingsSnapshot) throws
}

struct FileSettingsPersistenceAdapter: PersistenceAdapter {
    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    private struct VersionOneSettings: Decodable {
        let shortcuts: ShortcutPair
    }

    private struct LossyExceptionRule: Decodable {
        let value: ExceptionRule?

        init(value: ExceptionRule?) {
            self.value = value
        }

        init(from decoder: any Decoder) throws {
            value = try? ExceptionRule(from: decoder)
        }
    }

    private struct VersionTwoSettings: Decodable {
        let shortcuts: ShortcutPair
        let exceptionRules: [LossyExceptionRule]
    }

    private struct VersionThreeSettings: Decodable {
        let shortcuts: ShortcutPair
        let exceptionRules: [LossyExceptionRule]
        let general: GeneralSettings
    }

    let settingsURL: URL

    var diagnosticSettingsURL: URL {
        settingsURL.appendingPathExtension("invalid")
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

            let current: VersionThreeSettings
            switch version {
            case 1:
                let settings = try decoder.decode(VersionOneSettings.self, from: data)
                current = migrateToVersionThree(migrateToVersionTwo(settings))
            case 2:
                current = migrateToVersionThree(
                    try decoder.decode(VersionTwoSettings.self, from: data)
                )
            default:
                current = try decoder.decode(VersionThreeSettings.self, from: data)
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
            general: .defaults
        )
    }

    private func preserveSettingsForDiagnosis() {
        guard !FileManager.default.fileExists(atPath: diagnosticSettingsURL.path) else {
            return
        }
        try? FileManager.default.copyItem(
            at: settingsURL,
            to: diagnosticSettingsURL
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
