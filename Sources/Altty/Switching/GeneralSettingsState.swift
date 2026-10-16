struct GeneralSettingsState: Equatable, Sendable {
    var current: GeneralSettings
    var pending: GeneralSettings?
    var error: String?
    var recoveryWarning: String?
    var launchAtLoginRequiresApproval = false
    var mouseScrollStatus: MouseScrollStatus = .disabled
    var hintShortcutError: HintShortcutError?
    var hintShortcutUnavailable = false
    var mouseShortcutUnavailable = false

    func mouseModeMessage(accessibility: Availability) -> String? {
        guard displayed.mouseMode.enabled else { return nil }
        if displayed.mouseMode.shortcut == nil { return "Record a Mouse shortcut in Shortcuts to use Mouse Mode." }
        if accessibility != .available { return "Mouse Mode needs Accessibility permission." }
        return mouseShortcutUnavailable ? "Mouse Mode could not start. Secure Input may be active, or the shortcut may be unavailable. Check readiness and try again." : nil
    }

    var displayed: GeneralSettings { pending ?? current }
    var inlineMessage: String? { error ?? recoveryWarning }

    func mouseScrollMessage(accessibility: Availability) -> String? {
        guard current.reverseMouseWheel else { return nil }
        if accessibility != .available {
            return "Mouse wheel reversal needs Accessibility permission."
        }
        if mouseScrollStatus == .inputMonitoringRequired {
            return "Enable Altty in System Settings → Privacy & Security → Input Monitoring. If it is missing, use Show Altty in Finder to locate it."
        }
        if mouseScrollStatus == .unavailable {
            return "Mouse wheel reversal could not start. Check Accessibility and Input Monitoring permissions, then click Check Readiness."
        }
        return nil
    }

    func hintModeMessage(accessibility: Availability) -> String? {
        guard current.hintMode.enabled else { return nil }
        if current.hintMode.shortcut == nil {
            return "Record a Hint shortcut in Shortcuts to start using hints."
        }
        if accessibility != .available { return "Keyboard hints need Accessibility permission." }
        return hintShortcutUnavailable ? HintShortcutError.unavailable.message : nil
    }

    var hintShortcutMessage: String? {
        if let hintShortcutError { return hintShortcutError.message }
        if hintShortcutUnavailable { return HintShortcutError.unavailable.message }
        guard current.hintMode.shortcut != nil, !current.hintMode.enabled else { return nil }
        return "Turn on keyboard hints in General to use this shortcut."
    }
}
