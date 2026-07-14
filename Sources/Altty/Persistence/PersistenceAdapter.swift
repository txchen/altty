import Foundation

struct SettingsSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let defaults = SettingsSnapshot(shortcuts: .defaults)

    let version: Int
    let shortcuts: ShortcutPair

    init(version: Int = currentVersion, shortcuts: ShortcutPair) {
        self.version = version
        self.shortcuts = shortcuts
    }
}

enum SettingsLoadWarning: Equatable, Sendable {
    case malformed
    case unsupportedVersion(Int)
    case invalidShortcuts

    var message: String {
        switch self {
        case .malformed:
            "Settings could not be read. Safe shortcut defaults are active; the original file was preserved."
        case let .unsupportedVersion(version):
            "Settings version \(version) is not supported. Safe shortcut defaults are active; the original file was preserved."
        case .invalidShortcuts:
            "Saved shortcuts were invalid. Safe defaults are active; the original file was preserved."
        }
    }
}

struct SettingsLoadResult: Equatable, Sendable {
    let snapshot: SettingsSnapshot
    let warning: SettingsLoadWarning?
}

protocol PersistenceAdapter: Sendable {
    func loadSettings() -> SettingsLoadResult
    func saveSettings(_ snapshot: SettingsSnapshot) throws
}

struct FileSettingsPersistenceAdapter: PersistenceAdapter {
    private struct VersionEnvelope: Decodable {
        let version: Int
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
            guard version == SettingsSnapshot.currentVersion else {
                return SettingsLoadResult(
                    snapshot: .defaults,
                    warning: .unsupportedVersion(version)
                )
            }
            let snapshot = try decoder.decode(SettingsSnapshot.self, from: data)
            guard snapshot.shortcuts.validationError == nil else {
                return SettingsLoadResult(snapshot: .defaults, warning: .invalidShortcuts)
            }
            return SettingsLoadResult(snapshot: snapshot, warning: nil)
        } catch {
            return SettingsLoadResult(snapshot: .defaults, warning: .malformed)
        }
    }

    func saveSettings(_ snapshot: SettingsSnapshot) throws {
        guard snapshot.version == SettingsSnapshot.currentVersion,
              snapshot.shortcuts.validationError == nil else {
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
