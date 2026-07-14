import ServiceManagement

enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
}

@MainActor
protocol LaunchAtLoginAdapter: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus
    func openSystemSettings()
}

@MainActor
final class SystemLaunchAtLoginAdapter: LaunchAtLoginAdapter {
    var status: LaunchAtLoginStatus { Self.mapStatus(SMAppService.mainApp.status) }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func mapStatus(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }
}
