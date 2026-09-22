import AppKit
@testable import Altty

@MainActor final class ProbeRegistrar: HotKeyRegistrar {
    var keys: [RegisteredHotKey] = []
    func register(_ hotKey: RegisteredHotKey) -> Bool { keys.append(hotKey); return true }
    func unregister(id: UInt32) -> Bool { true }
}

@main struct InputOrderProbe {
    @MainActor static func main() {
        let registrar = ProbeRegistrar()
        let input = SystemInputAdapter(registrar: registrar, usesSystemMonitors: false)
        var events: [ShortcutEvent] = []
        input.install { events.append($0) }
        _ = input.setShortcutsEnabled(true)
        let id = registrar.keys[0].id
        // Synthetic callback order: a physical release is delivered before its delayed Carbon hotkey.
        input.modifiersChanged([])
        _ = input.hotKeyPressed(id: id)
        let released = events.contains(.holdModifiersReleased)
        print("release-before-hotkey: eventCount=\(events.count), confirmationEmitted=\(released)")
        input.modifiersChanged([])
        print("after another release: confirmationEmitted=\(events.contains(.holdModifiersReleased))")
        _ = input.setShortcutsEnabled(false)
    }
}
