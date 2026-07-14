import Foundation

struct SettingsSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 2
    static let defaults = SettingsSnapshot(shortcuts: .defaults, exceptionRules: [])

    let version: Int
    let shortcuts: ShortcutPair
    let exceptionRules: [ExceptionRule]

    init(
        version: Int = currentVersion,
        shortcuts: ShortcutPair,
        exceptionRules: [ExceptionRule] = []
    ) {
        self.version = version
        self.shortcuts = shortcuts
        self.exceptionRules = exceptionRules
    }

    var isValid: Bool {
        shortcuts.validationError == nil
            && Set(exceptionRules.map(\.identity)).count == exceptionRules.count
    }
}

enum SettingsLoadWarning: Equatable, Sendable {
    case malformed
    case unsupportedVersion(Int)
    case invalidShortcuts
    case invalidExceptionRules(discardedCount: Int)

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

        init(from decoder: any Decoder) throws {
            value = try? ExceptionRule(from: decoder)
        }
    }

    private struct VersionTwoSettings: Decodable {
        let shortcuts: ShortcutPair
        let exceptionRules: [LossyExceptionRule]
    }

    let settingsURL: URL

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
                return SettingsLoadResult(
                    snapshot: .defaults,
                    warning: .unsupportedVersion(version)
                )
            }
            if version == 1 {
                let settings = try decoder.decode(VersionOneSettings.self, from: data)
                guard settings.shortcuts.validationError == nil else {
                    return SettingsLoadResult(snapshot: .defaults, warning: .invalidShortcuts)
                }
                return SettingsLoadResult(
                    snapshot: SettingsSnapshot(shortcuts: settings.shortcuts),
                    warning: nil
                )
            }

            let settings = try decoder.decode(VersionTwoSettings.self, from: data)
            guard settings.shortcuts.validationError == nil else {
                return SettingsLoadResult(snapshot: .defaults, warning: .invalidShortcuts)
            }
            var rules: [ExceptionRule] = []
            var discardedCount = 0
            for decoded in settings.exceptionRules {
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
                    shortcuts: settings.shortcuts,
                    exceptionRules: rules
                ),
                warning: discardedCount == 0
                    ? nil
                    : .invalidExceptionRules(discardedCount: discardedCount)
            )
        } catch {
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
