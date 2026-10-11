import Foundation

/// Registers at most one global Hint Shortcut. `setShortcut` converges to the
/// requested binding (nil unregisters) and returns whether that state was reached.
@MainActor
protocol HintShortcutAdapter: AnyObject {
    func install(onPress: @escaping @MainActor () -> Void)
    func setShortcut(_ binding: ShortcutBinding?) -> Bool
}

/// Owns Hint Sessions: scanning, overlay, keyboard capture and actions.
/// `setShortcut` mirrors the registered Hint Shortcut so an active session can
/// recognise its own chord; nil also ends any active session.
@MainActor
protocol HintSessionController: AnyObject {
    func setShortcut(_ binding: ShortcutBinding?)
    func toggleSession()
    func endSession()
}
