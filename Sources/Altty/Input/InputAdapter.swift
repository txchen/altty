import Foundation

@MainActor
protocol InputAdapter: AnyObject { func setShortcutsEnabled(_ enabled: Bool) }

@MainActor
final class SystemInputAdapter: InputAdapter {
    private(set) var shortcutsEnabled = false
    func setShortcutsEnabled(_ enabled: Bool) { shortcutsEnabled = enabled }
}
