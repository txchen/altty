import Foundation

@MainActor
protocol SwitchingAdapter: AnyObject { func endActiveSession() }

@MainActor
final class SystemSwitchingAdapter: SwitchingAdapter {
    func endActiveSession() {}
}
