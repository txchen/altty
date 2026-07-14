import ServiceManagement

enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
}

enum LaunchAtLoginOperation: Equatable, Sendable {
    case none
    case register
    case unregister
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
        switch Self.requiredOperation(enabled: enabled, status: status) {
        case .none:
            return status
        case .register:
            try SMAppService.mainApp.register()
        case .unregister:
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

    static func requiredOperation(
        enabled: Bool,
        status: LaunchAtLoginStatus
    ) -> LaunchAtLoginOperation {
        switch (enabled, status) {
        case (true, .enabled), (false, .disabled): .none
        case (true, _): .register
        case (false, _): .unregister
        }
    }
}
