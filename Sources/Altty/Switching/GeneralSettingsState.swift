struct GeneralSettingsState: Equatable, Sendable {
    var current: GeneralSettings
    var pending: GeneralSettings?
    var error: String?
    var recoveryWarning: String?
    var launchAtLoginRequiresApproval = false
    var mouseScrollStatus: MouseScrollStatus = .disabled

    var displayed: GeneralSettings { pending ?? current }
    var inlineMessage: String? { error ?? recoveryWarning }

    func mouseScrollMessage(accessibility: Availability) -> String? {
        guard current.reverseMouseWheel else { return nil }
        if accessibility != .available {
            return "Mouse wheel reversal needs Accessibility permission."
        }
        if mouseScrollStatus == .inputMonitoringRequired {
            return "Allow Altty in Privacy & Security > Input Monitoring, then click Check Readiness."
        }
        if mouseScrollStatus == .unavailable {
            return "Mouse wheel reversal could not start. Check Accessibility and Input Monitoring permissions, then click Check Readiness."
        }
        return nil
    }
}
