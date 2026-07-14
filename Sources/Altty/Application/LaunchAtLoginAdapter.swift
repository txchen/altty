import ServiceManagement

enum LaunchAtLoginError: Error {
    case statusDidNotChange
}

@MainActor
protocol LaunchAtLoginAdapter: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class SystemLaunchAtLoginAdapter: LaunchAtLoginAdapter {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        guard isEnabled == enabled else { throw LaunchAtLoginError.statusDidNotChange }
    }
}
