// Standalone QA application. Never linked into Altty or packaged with releases.
import AppKit

@MainActor final class HostileAppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var created = 0
    private var destroyed = 0
    private let output: URL
    private let count: Int
    private let cycles: Int
    private let stallMilliseconds: Int
    private let lifetime: Double

    init(output: URL, count: Int, cycles: Int, stallMilliseconds: Int, lifetime: Double) {
        self.output = output; self.count = count; self.cycles = cycles
        self.stallMilliseconds = stallMilliseconds; self.lifetime = lifetime
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        for i in 0..<count { windows.append(makeWindow(i)) }
        publish("ready")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            publish("stalling")
            // A real main-thread stall prevents the remote AX service from answering.
            Thread.sleep(forTimeInterval: Double(stallMilliseconds) / 1_000)
            publish("recovered")
            for i in 0..<cycles {
                let window = makeWindow(i + count)
                window.close(); destroyed += 1
            }
            publish("churn-complete")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [self] in
            windows.forEach { $0.close(); destroyed += 1 }
            windows.removeAll()
            publish("finished")
            NSApp.terminate(nil)
        }
    }
    private func makeWindow(_ index: Int) -> NSWindow {
        let panel = NSWindow(contentRect: .init(x: 80 + index % 8 * 24, y: 100 + index % 8 * 24, width: 360, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "Altty QA Window \(index)"
        let label = NSTextField(labelWithString: "Synthetic window — AX stall / lifecycle fixture")
        label.frame = .init(x: 16, y: 70, width: 330, height: 30)
        panel.contentView?.addSubview(label)
        panel.orderFront(nil)
        created += 1
        return panel
    }
    private func publish(_ phase: String) {
        let report: [String: Any] = ["phase": phase, "pid": ProcessInfo.processInfo.processIdentifier,
            "windows": windows.map(\.windowNumber), "created": created, "destroyed": destroyed]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            try data.write(to: output, options: .atomic)
            print(String(decoding: data, as: UTF8.self))
            fflush(stdout)
        } catch { fputs("fixture report failed\n", stderr); NSApp.terminate(nil) }
    }
}

@main struct HostileWindowApp {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 5, let count = Int(args[1]), (1...20).contains(count),
              let cycles = Int(args[2]), (0...1_000).contains(cycles),
              let stall = Int(args[3]), (0...5_000).contains(stall),
              let lifetime = Double(args[4]), lifetime >= Double(stall) / 1_000 + 1, lifetime <= 60 else {
            fputs("usage: HostileWindowApp report.json windows(1-20) cycles(0-1000) stall_ms(0-5000) lifetime_s\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        let delegate = HostileAppDelegate(output: URL(fileURLWithPath: args[0]), count: count, cycles: cycles,
            stallMilliseconds: stall, lifetime: lifetime)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
