struct GeneralSettingsState: Equatable, Sendable {
    var current: GeneralSettings
    var pending: GeneralSettings?
    var error: String?
    var recoveryWarning: String?
    var launchAtLoginRequiresApproval = false

    var displayed: GeneralSettings { pending ?? current }
    var inlineMessage: String? { error ?? recoveryWarning }
}
