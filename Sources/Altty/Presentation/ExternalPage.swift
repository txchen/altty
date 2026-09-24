import AppKit

enum ExternalPage: Equatable, Sendable {
    case project
    case support

    var url: URL {
        switch self {
        case .project: URL(string: "https://github.com/txchen/altty")!
        case .support: URL(string: "https://github.com/txchen/altty/issues")!
        }
    }
}
