import Foundation

enum ExceptionMatchType: String, CaseIterable, Codable, Equatable, Sendable {
    case exact
    case prefix

    var title: String {
        switch self {
        case .exact: "Exact"
        case .prefix: "Prefix"
        }
    }
}

enum ExceptionIgnore: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case whenFullscreen
    case always

    fileprivate var strength: Int {
        switch self {
        case .none: 0
        case .whenFullscreen: 1
        case .always: 2
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .whenFullscreen: "When Fullscreen"
        case .always: "Always"
        }
    }
}

struct ExceptionRuleIdentity: Codable, Equatable, Hashable, Sendable {
    let bundleIdentifier: String
    let matchType: ExceptionMatchType
}

struct ExceptionRule: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let matchType: ExceptionMatchType
    let hide: Bool
    let ignore: ExceptionIgnore

    init?(
        bundleIdentifier: String,
        matchType: ExceptionMatchType,
        hide: Bool,
        ignore: ExceptionIgnore
    ) {
        let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }
        self.bundleIdentifier = identifier
        self.matchType = matchType
        self.hide = hide
        self.ignore = ignore
    }

    var identity: ExceptionRuleIdentity {
        ExceptionRuleIdentity(bundleIdentifier: bundleIdentifier, matchType: matchType)
    }

    var summary: String {
        let hideSummary = hide ? "Hide" : "Show"
        let ignoreSummary = switch ignore {
        case .none: "shortcuts active"
        case .whenFullscreen: "ignore fullscreen"
        case .always: "always ignore"
        }
        return "\(hideSummary) · \(ignoreSummary)"
    }

    static func replacingDuplicateIdentity(
        in rules: [ExceptionRule],
        with replacement: ExceptionRule,
        replacing originalIdentity: ExceptionRuleIdentity? = nil
    ) -> [ExceptionRule] {
        var result = rules
        if let originalIdentity,
           originalIdentity != replacement.identity {
            result.removeAll { $0.identity == originalIdentity }
        }
        if let index = result.firstIndex(where: { $0.identity == replacement.identity }) {
            result[index] = replacement
        } else {
            result.append(replacement)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case matchType
        case hide
        case ignore
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let bundleIdentifier = try values.decode(String.self, forKey: .bundleIdentifier)
        let matchType = try values.decode(ExceptionMatchType.self, forKey: .matchType)
        let hide = try values.decode(Bool.self, forKey: .hide)
        let ignore = try values.decode(ExceptionIgnore.self, forKey: .ignore)
        guard let rule = ExceptionRule(
            bundleIdentifier: bundleIdentifier,
            matchType: matchType,
            hide: hide,
            ignore: ignore
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .bundleIdentifier,
                in: values,
                debugDescription: "Exception bundle identifier must not be empty."
            )
        }
        self = rule
    }
}

struct ExceptionDisposition: Equatable, Sendable {
    static let none = ExceptionDisposition(hidesWindows: false, ignore: .none)

    let hidesWindows: Bool
    let ignore: ExceptionIgnore
}

struct ExceptionForegroundContext: Equatable, Sendable {
    static let unknown = ExceptionForegroundContext(
        bundleIdentifier: nil,
        windowIsFullscreen: nil
    )

    let bundleIdentifier: String?
    let windowIsFullscreen: Bool?
}

struct ExceptionPolicy: Equatable, Sendable {
    let rules: [ExceptionRule]

    func disposition(for bundleIdentifier: String?) -> ExceptionDisposition {
        guard let bundleIdentifier else { return .none }
        var disposition = ExceptionDisposition.none
        for rule in rules where rule.matches(bundleIdentifier) {
            disposition = ExceptionDisposition(
                hidesWindows: disposition.hidesWindows || rule.hide,
                ignore: rule.ignore.strength > disposition.ignore.strength
                    ? rule.ignore
                    : disposition.ignore
            )
        }
        return disposition
    }

    func shortcutsShouldBeEnabled(in context: ExceptionForegroundContext) -> Bool? {
        switch disposition(for: context.bundleIdentifier).ignore {
        case .none:
            true
        case .always:
            false
        case .whenFullscreen:
            context.windowIsFullscreen.map { !$0 }
        }
    }
}

struct ExceptionSettingsState: Equatable, Sendable {
    var current: [ExceptionRule]
    var pending: [ExceptionRule]?
    var error: String?
    var recoveryWarning: String?

    var displayedRules: [ExceptionRule] { pending ?? current }
    var inlineMessage: String? { error ?? recoveryWarning }
}

struct ExceptionApplication: Equatable, Sendable {
    let bundleIdentifier: String
    let name: String
    let bundlePath: String?
}

@MainActor
protocol ExceptionsAdapter: AnyObject {
    func runningExceptionApplications() -> [ExceptionApplication]
    func exceptionApplication(bundleIdentifier: String) -> ExceptionApplication?
    func exceptionApplication(at bundleURL: URL) -> ExceptionApplication?
    func frontmostApplicationBundleIdentifier() -> String?
}

private extension ExceptionRule {
    func matches(_ candidate: String) -> Bool {
        switch matchType {
        case .exact: candidate == bundleIdentifier
        case .prefix: candidate.hasPrefix(bundleIdentifier)
        }
    }
}
