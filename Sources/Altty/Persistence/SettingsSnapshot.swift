import Foundation

enum ListSize: String, Codable, CaseIterable, Equatable, Sendable {
    case small, medium, large, auto

    var rowHeight: Double {
        switch self {
        case .small: 52
        case .medium: 60
        case .large, .auto: 68
        }
    }
}

struct ListPresentationPreferences: Codable, Equatable, Sendable {
    static let defaults = ListPresentationPreferences(size: .auto)
    let size: ListSize

    init(size: ListSize) { self.size = size }

    private enum CodingKeys: String, CodingKey { case size, density }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.size) {
            size = try values.decode(ListSize.self, forKey: .size)
        } else {
            // Preserve the old visual density; the fixed row limit is retired.
            let density = try values.decode(String.self, forKey: .density)
            switch density {
            case "compact": size = .small
            case "comfortable": size = .medium
            default: throw DecodingError.dataCorruptedError(forKey: .density, in: values,
                debugDescription: "Unknown list density")
            }
        }
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(size, forKey: .size)
    }

    var isValid: Bool { true }
}

struct GeneralSettings: Codable, Equatable, Sendable {
    static let defaults = GeneralSettings(
        launchAtLogin: false,
        listPresentation: .defaults,
        hintMode: .disabled
    )

    let launchAtLogin: Bool
    let listPresentation: ListPresentationPreferences
    let reverseMouseWheel: Bool
    let diagnosticLoggingEnabled: Bool
    let hintMode: HintModeSettings

    init(
        launchAtLogin: Bool,
        listPresentation: ListPresentationPreferences,
        reverseMouseWheel: Bool = false,
        diagnosticLoggingEnabled: Bool = false,
        hintMode: HintModeSettings
    ) {
        self.launchAtLogin = launchAtLogin
        self.listPresentation = listPresentation
        self.reverseMouseWheel = reverseMouseWheel
        self.diagnosticLoggingEnabled = diagnosticLoggingEnabled
        self.hintMode = hintMode
    }

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, listPresentation, reverseMouseWheel, diagnosticLoggingEnabled, hintMode
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try values.decode(Bool.self, forKey: .launchAtLogin)
        listPresentation = try values.decode(ListPresentationPreferences.self, forKey: .listPresentation)
        reverseMouseWheel = try values.decode(Bool.self, forKey: .reverseMouseWheel)
        diagnosticLoggingEnabled = try values.decodeIfPresent(Bool.self, forKey: .diagnosticLoggingEnabled) ?? false
        hintMode = try values.decodeIfPresent(HintModeSettings.self, forKey: .hintMode) ?? .disabled
    }

    var isValid: Bool { listPresentation.isValid }
}

struct SettingsSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 5
    static let defaults = SettingsSnapshot(
        shortcuts: .defaults,
        exceptionRules: ExceptionRule.defaults,
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
            && general.hintMode.validationError(against: shortcuts) == nil
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
