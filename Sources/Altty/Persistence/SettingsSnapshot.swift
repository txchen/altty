import Foundation

enum ListDensity: String, Codable, CaseIterable, Equatable, Sendable {
    case compact
    case comfortable
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
            "Settings could not be read. Safe defaults are active; the original file was preserved."
        case let .unsupportedVersion(version):
            "Settings version \(version) is not supported. Safe defaults are active; the original file was preserved."
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
