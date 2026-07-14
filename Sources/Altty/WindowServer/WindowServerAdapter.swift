import Foundation

@MainActor
protocol WindowServerAdapter: AnyObject { func availability() -> Availability }

@MainActor
final class SystemWindowServerAdapter: WindowServerAdapter {
    // Ticket 11 supplies the isolated, runtime-resolved SkyLight implementation.
    func availability() -> Availability { .unavailable }
}
