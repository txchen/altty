import AppKit
import CoreGraphics

@MainActor
protocol MousePointer: AnyObject {
    var position: CGPoint { get }
    var screens: [CGRect] { get }
    func move(to point: CGPoint)
    func click(_ button: CGMouseButton)
}

@MainActor
final class SystemMousePointer: MousePointer {
    var position: CGPoint { CGEvent(source: nil)?.location ?? .zero }
    var screens: [CGRect] { HintGeometry.axScreenFrames() }
    func move(to point: CGPoint) {
        post(.mouseMoved, at: point, button: .left)
    }
    func click(_ button: CGMouseButton) {
        let point = position
        post(button == .left ? .leftMouseDown : .rightMouseDown, at: point, button: button)
        post(button == .left ? .leftMouseUp : .rightMouseUp, at: point, button: button)
    }
    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        event?.setIntegerValueField(.eventSourceUserData, value: HintEventMarker.userData)
        event?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class SystemMouseSessionController {
    enum Phase {
        case movement
        case scanning([HintKey])
        case picking(MouseHintPicker)
    }
    private let scanner: any HintScanner
    private let overlay: any HintOverlay
    private let tap: any HintKeyboardTap
    private let pointer: any MousePointer
    private let workspace: any HintWorkspace
    private let clock: any HintClock
    private var timer: Timer?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    private var shortcut: ShortcutBinding?
    private var classifier = HintKeyClassifier(shortcut: nil, initialFlags: [])
    private var generation = 0
    private var scanPID: pid_t?
    private var targets: [HintTarget] = []
    private var movement = MouseMovement()
    private var lastTick: TimeInterval = 0
    private var position: CGPoint?
    private var lastPostedPosition: CGPoint?
    private var ignoresTogglesUntil = -TimeInterval.infinity
    private(set) var phase: Phase?
    var onActivityChanged: (@MainActor (Bool) -> Void)?
    var onStart: (@MainActor () -> Void)?
    var onFailure: (@MainActor () -> Void)?
    var isActive: Bool { phase != nil }

    init(
        scanner: any HintScanner = AXHintScanner(), overlay: any HintOverlay = PanelHintOverlay(),
        tap: any HintKeyboardTap = CoreGraphicsHintKeyboardTap(), pointer: any MousePointer = SystemMousePointer(),
        workspace: any HintWorkspace = SystemHintWorkspace(),
        clock: any HintClock = SystemHintClock()
    ) {
        self.scanner = scanner
        self.overlay = overlay
        self.tap = tap
        self.pointer = pointer
        self.workspace = workspace
        self.clock = clock
    }
    func setShortcut(_ binding: ShortcutBinding?) {
        if shortcut != binding { endSession() }
        shortcut = binding
    }
    func toggleSession() {
        guard clock.now >= ignoresTogglesUntil else { return }
        if isActive {
            endSession()
            return
        }
        guard shortcut != nil else { return }
        guard !workspace.isSecureInputEnabled else {
            fail()
            return
        }
        phase = .movement
        classifier = HintKeyClassifier(shortcut: shortcut, initialFlags: tap.currentFlags)
        guard
            tap.start(
                onEvent: { [weak self] in self?.receive($0) ?? false },
                onFailure: { [weak self] in self?.fail() })
        else {
            fail()
            return
        }
        onActivityChanged?(true)
        onStart?()
        lastTick = clock.now
        let timer = Timer(timeInterval: 1 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        workspace.observeActivations { [weak self] pid in
            guard let self, self.isActive else { return }
            if case .movement = self.phase {} else if pid != self.scanPID { self.resumeMovement() }
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"))
    }
    func endSession() {
        guard isActive else { return }
        generation &+= 1
        phase = nil
        onActivityChanged?(false)
        movement = MouseMovement()
        position = nil
        lastPostedPosition = nil
        timer?.invalidate()
        timer = nil
        targets = []
        overlay.hide()
        workspace.stopObservingActivations()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        tap.stop()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endSession() }
        }
        observers.append((center, observer))
    }
    private func fail() {
        endSession()
        workspace.beep()
        onFailure?()
    }

    func tick() {
        guard isActive else { return }
        guard !workspace.isSecureInputEnabled else {
            fail()
            return
        }
        let now = clock.now
        let elapsed = min(max(now - lastTick, 0), 0.05)
        lastTick = now
        guard case .movement = phase else { return }
        let direction = movement.direction
        guard direction != .zero else {
            position = nil
            lastPostedPosition = nil
            return
        }
        let actual = pointer.position
        if position == nil || lastPostedPosition.map({ hypot($0.x - actual.x, $0.y - actual.y) > 2 }) == true {
            position = actual
        }
        let old = position ?? actual
        let distance = movement.speed.pointsPerSecond * elapsed
        let next = MouseScreenGeometry.project(
            CGPoint(
                x: old.x + direction.dx * distance,
                y: old.y + direction.dy * distance), onto: pointer.screens)
        position = next
        pointer.move(to: next)
        lastPostedPosition = next
    }
    private func receive(_ event: HintTapEvent) -> Bool {
        guard isActive else { return false }
        guard !workspace.isSecureInputEnabled else {
            fail()
            return false
        }
        guard case .key(let raw) = event else { return false }
        if raw.kind == .keyUp {
            movement.held.remove(raw.keyCode)
            return false
        }
        guard raw.kind == .keyDown else { return false }
        guard let key = classifier.classify(raw) else { return false }
        if key == .hintShortcut {
            ignoresTogglesUntil = clock.now + 0.3
            endSession()
            return true
        }
        if !raw.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            endSession()
            return false
        }
        if key == .escape {
            if case .movement = phase { endSession() } else { resumeMovement() }
            return true
        }
        switch phase {
        case .movement:
            if MouseMovement.controls.contains(raw.keyCode) {
                movement.held.insert(raw.keyCode)
            } else if raw.keyCode == MouseKey.leftClick {
                pointer.click(.left)
            } else if raw.keyCode == MouseKey.rightClick {
                pointer.click(.right)
            } else if raw.keyCode == MouseKey.hints {
                beginHints()
            }
        case .scanning(var buffer):
            buffer.append(key)
            phase = .scanning(buffer)
        case .picking:
            pick(key)
        case nil: break
        }
        return true
    }
    private func beginHints() {
        movement = MouseMovement()
        position = nil
        lastPostedPosition = nil
        generation &+= 1
        let token = generation
        guard let pid = workspace.frontmostPID else {
            resumeMovement()
            return
        }
        scanPID = pid
        phase = .scanning([])
        scanner.scan(pid: pid) { [weak self] result in
            guard let self, token == self.generation, case .scanning(let buffer) = self.phase else { return }
            self.targets = Array(result.targets.prefix(HintLabels.capacity()))
            guard !self.targets.isEmpty else {
                self.workspace.beep()
                self.resumeMovement()
                return
            }
            self.phase = .picking(MouseHintPicker(count: self.targets.count))
            for key in buffer {
                guard case .picking = self.phase else { break }
                self.pick(key)
            }
            self.redrawPicker()
        }
    }
    private func pick(_ key: HintKey) {
        guard case .picking(var picker) = phase else { return }
        if let index = picker.handle(key) {
            let frame = targets[index].frame
            pointer.move(to: MouseScreenGeometry.project(CGPoint(x: frame.midX, y: frame.midY), onto: pointer.screens))
            resumeMovement()
        } else {
            phase = .picking(picker)
            redrawPicker()
        }
    }
    private func resumeMovement() {
        generation &+= 1
        movement = MouseMovement()
        position = nil
        lastPostedPosition = nil
        targets = []
        phase = .movement
        overlay.hide()
    }
    private func redrawPicker() {
        guard case .picking(let picker) = phase else { return }
        overlay.show(
            picker.badges.map { badge in
                HintOverlayItem(
                    label: badge.label, typedCount: badge.typedCount,
                    frame: targets[badge.target].frame, isSelected: false)
            })
    }
}
