import AppKit
import Carbon.HIToolbox

final class SwitcherPanel: NSPanel {
    var onMoveSelection: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Tab, kVK_DownArrow, kVK_RightArrow:
            onMoveSelection?(event.modifierFlags.contains(.shift) ? -1 : 1)
        case kVK_UpArrow, kVK_LeftArrow:
            onMoveSelection?(-1)
        case kVK_Return, kVK_Space:
            onConfirm?()
        case kVK_Escape:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}
