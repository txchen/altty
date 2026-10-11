import CoreGraphics
import Foundation

/// Runs Hint Sessions: keyboard capture starts with the shortcut press, the
/// scan runs meanwhile, and keys typed before it finishes are replayed. Each
/// session has a monotonic token so late scans and timers from an ended
/// session are discarded.
@MainActor
final class SystemHintSessionController: HintSessionController {
    /// Carbon can deliver the same shortcut press the tap already used to end
    /// a session; a toggle this soon after is that press, not a new one.
    static let shortcutEchoWindow: TimeInterval = 0.3

    private let scanner: any HintScanner
    private let overlay: any HintOverlay
    private let tap: any HintKeyboardTap
    private let performer: any HintActionPerformer
    private let workspace: any HintWorkspace
    private let clock: any HintClock

    private var shortcut: ShortcutBinding?
    private var token = 0
    private var capture: HintCapture?
    private var classifier = HintKeyClassifier(shortcut: nil, initialFlags: [])
    private var targets: [HintTarget] = []
    private var ignoresTogglesUntil = -TimeInterval.infinity

    init(
        scanner: any HintScanner = AXHintScanner(),
        overlay: any HintOverlay = PanelHintOverlay(),
        tap: any HintKeyboardTap = CoreGraphicsHintKeyboardTap(),
        performer: any HintActionPerformer = SystemHintActionPerformer(),
        workspace: any HintWorkspace = SystemHintWorkspace(),
        clock: any HintClock = SystemHintClock()
    ) {
        self.scanner = scanner
        self.overlay = overlay
        self.tap = tap
        self.performer = performer
        self.workspace = workspace
        self.clock = clock
    }

    var isActive: Bool { capture != nil }

    func setShortcut(_ binding: ShortcutBinding?) {
        shortcut = binding
        classifier.shortcut = binding
        if binding == nil { endSession() }
    }

    func toggleSession() {
        guard clock.now >= ignoresTogglesUntil else { return }
        if capture != nil {
            endSession()
        } else {
            startSession()
        }
    }

    func endSession() {
        guard capture != nil else { return }
        token &+= 1
        capture = nil
        targets = []
        tap.stop()
        overlay.hide()
        workspace.stopObservingActivations()
    }

    private func startSession() {
        token &+= 1
        let session = token
        capture = .started
        classifier = HintKeyClassifier(shortcut: shortcut, initialFlags: tap.currentFlags)
        let started = tap.start(
            onEvent: { [weak self] event in self?.receive(event) ?? false },
            onFailure: { [weak self] in self?.endSession() }
        )
        guard started, !workspace.isSecureInputEnabled, let pid = workspace.frontmostPID else {
            endSession()
            workspace.beep()
            return
        }
        // The notice for the activation that made `pid` frontmost can still be
        // queued when the shortcut is pressed right after an app switch.
        workspace.observeActivations { [weak self] activated in
            if activated != pid { self?.endSession() }
        }
        scanner.scan(pid: pid) { [weak self] result in
            self?.scanFinished(result, session: session)
        }
    }

    private func scanFinished(_ result: HintScanResult, session: Int) {
        guard session == token, var capture else { return }
        let targets = Array(result.targets.prefix(HintLabels.capacity()))
        guard !targets.isEmpty else {
            endSession()
            workspace.beep()
            return
        }
        self.targets = targets
        let steps = capture.scanFinished(defaultActions: targets.map(\.defaultAction))
        self.capture = capture
        for step in steps {
            apply(step, redraws: false)
            guard session == token else { return }
        }
        redraw()
    }

    private func receive(_ event: HintTapEvent) -> Bool {
        guard var capture else { return false }
        switch event {
        case .mouseDown:
            endSession()
            return false
        case let .key(raw):
            guard let key = classifier.classify(raw) else { return false }
            let step = capture.handle(key)
            self.capture = capture
            if key == .hintShortcut, step.swallow, step.next == .end {
                ignoresTogglesUntil = clock.now + Self.shortcutEchoWindow
            }
            apply(step)
            return step.swallow
        }
    }

    private func apply(_ step: HintStep, redraws: Bool = true) {
        if let perform = step.perform {
            performer.perform(perform.action, on: targets[perform.target])
        }
        switch step.next {
        case .stay:
            if step.redraw, redraws { redraw() }
        case .awaitSecondClick:
            overlay.hide()
            let session = token
            clock.schedule(after: workspace.doubleClickInterval) { [weak self] in
                self?.doubleClickWindowEnded(session: session)
            }
        case .end:
            endSession()
        }
    }

    private func doubleClickWindowEnded(session: Int) {
        guard session == token, var capture else { return }
        let expired = capture.doubleClickWindowExpired()
        self.capture = capture
        if expired { endSession() }
    }

    private func redraw() {
        guard let session = capture?.session else { return }
        let items = session.badges.map { badge in
            HintOverlayItem(
                label: badge.label,
                typedCount: badge.typedCount,
                frame: targets[badge.target].frame,
                isSelected: badge.isSelected
            )
        }
        if items.isEmpty {
            overlay.hide()
        } else {
            overlay.show(items)
        }
    }
}
