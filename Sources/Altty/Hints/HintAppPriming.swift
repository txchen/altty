import ApplicationServices
import Foundation

/// Electron and Chromium build their AX tree lazily: Electron only for
/// `AXManualAccessibility`, Chromium browsers for `AXEnhancedUserInterface`.
enum HintAppKind: Equatable, Sendable {
    case electron
    case chromium
    case other

    private static let chromiumBundlePrefixes = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "org.chromium.Chromium",
    ]

    var buildsTreeLazily: Bool { self != .other }

    static func classify(
        bundleIdentifier: String?,
        frameworkNames: [String],
        hasChromiumAppModeLoader: Bool
    ) -> HintAppKind {
        if frameworkNames.contains("Electron Framework.framework") { return .electron }
        if hasChromiumAppModeLoader { return .chromium }
        if let bundleIdentifier, chromiumBundlePrefixes.contains(where: bundleIdentifier.hasPrefix) {
            return .chromium
        }
        return .other
    }

    /// Chromium browsers ship `<Name> Framework.framework/Helpers/app_mode_loader`;
    /// Electron and other embedders do not.
    static func inspect(bundleURL: URL?, bundleIdentifier: String?) -> HintAppKind {
        let files = FileManager.default
        let frameworks = bundleURL?.appending(path: "Contents/Frameworks", directoryHint: .isDirectory)
        let names = frameworks.flatMap { try? files.contentsOfDirectory(atPath: $0.path) } ?? []
        let hasLoader = frameworks.map { directory in
            names.contains { name in
                name.hasSuffix(" Framework.framework")
                    && files.fileExists(atPath: directory.appending(path: "\(name)/Helpers/app_mode_loader").path)
            }
        } ?? false
        return classify(bundleIdentifier: bundleIdentifier, frameworkNames: names, hasChromiumAppModeLoader: hasLoader)
    }
}

/// Sets the attribute that makes a lazy app expose its tree. Only touched on
/// the scan queue.
final class HintAppPrimer: @unchecked Sendable {
    private static let manualAccessibility = "AXManualAccessibility"
    private static let enhancedUserInterface = "AXEnhancedUserInterface"
    private static let timeout: Float = 0.2

    private var manuallyAccessiblePIDs: Set<pid_t> = []

    /// Returns the undo for anything that must not outlive the scan.
    func prime(_ application: AXUIElement, pid: pid_t, kind: HintAppKind) -> () -> Void {
        AXUIElementSetMessagingTimeout(application, Self.timeout)
        switch kind {
        case .other:
            return {}
        case .electron:
            if !manuallyAccessiblePIDs.contains(pid),
               AXUIElementSetAttributeValue(application, Self.manualAccessibility as CFString, kCFBooleanTrue) == .success {
                manuallyAccessiblePIDs.insert(pid)
            }
            return {}
        case .chromium:
            var value: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(application, Self.enhancedUserInterface as CFString, &value)
            let previous = read == .success ? (value as? Bool) ?? false : false
            guard !previous,
                  AXUIElementSetAttributeValue(application, Self.enhancedUserInterface as CFString, kCFBooleanTrue) == .success
            else { return {} }
            return {
                AXUIElementSetMessagingTimeout(application, Self.timeout)
                AXUIElementSetAttributeValue(application, Self.enhancedUserInterface as CFString, kCFBooleanFalse)
            }
        }
    }
}
