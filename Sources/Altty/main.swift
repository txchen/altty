import AppKit

let application = NSApplication.shared
let delegate = AppDelegate(environment: .production())
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
