import AppKit

@MainActor
protocol UpdateAction: AnyObject {
    func checkForUpdates()
}

@MainActor
final class GitHubReleaseUpdateAction: UpdateAction {
    static let latestReleaseURL = URL(
        string: "https://github.com/txchen/altty/releases/latest"
    )!

    private let openURL: (URL) -> Bool

    init(openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.openURL = openURL
    }

    func checkForUpdates() {
        _ = openURL(Self.latestReleaseURL)
    }
}
