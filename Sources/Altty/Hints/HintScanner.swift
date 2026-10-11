import AppKit
import ApplicationServices

struct HintScanResult: Sendable {
    static let empty = HintScanResult(targets: [], sawWebArea: false, visits: 0)

    /// On-screen targets in reading order.
    let targets: [HintTarget]
    let sawWebArea: Bool
    let visits: Int
}

@MainActor
protocol HintScanner: AnyObject {
    /// Scans the Hint Scope of `pid`; the completion runs on the main actor.
    func scan(pid: pid_t, completion: @escaping @MainActor @Sendable (HintScanResult) -> Void)
}

/// Remote AX IPC runs on a dedicated serial queue, never the main thread or the
/// cooperative pool. The whole scan shares one deadline.
@MainActor
final class AXHintScanner: HintScanner {
    nonisolated static let deadline: Duration = .milliseconds(1500)
    private nonisolated static let lazyTreeRetries = 3
    private nonisolated static let lazyTreeRetryDelay: TimeInterval = 0.1

    private let queue = DispatchQueue(label: "app.altty.hints.scan", qos: .userInteractive)
    private let primer = HintAppPrimer()

    func scan(pid: pid_t, completion: @escaping @MainActor @Sendable (HintScanResult) -> Void) {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
            completion(.empty)
            return
        }
        let screens = HintGeometry.axScreenFrames()
        let application = NSRunningApplication(processIdentifier: pid)
        let bundleURL = application?.bundleURL
        let bundleIdentifier = application?.bundleIdentifier
        let primer = primer
        queue.async {
            let result = autoreleasepool {
                let kind = HintAppKind.inspect(bundleURL: bundleURL, bundleIdentifier: bundleIdentifier)
                return Self.scan(pid: pid, kind: kind, screens: screens, primer: primer)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private nonisolated static func scan(
        pid: pid_t,
        kind: HintAppKind,
        screens: [CGRect],
        primer: HintAppPrimer
    ) -> HintScanResult {
        let budget = HintScanBudget(duration: deadline)
        let application = AXUIElementCreateApplication(pid)
        let restore = primer.prime(application, pid: pid, kind: kind)
        defer { restore() }
        var result = HintScopeScan.run(application: application, screens: screens, budget: budget)
        var retries = 0
        while kind.buildsTreeLazily, !result.sawWebArea, retries < lazyTreeRetries,
              budget.remainingSeconds > lazyTreeRetryDelay {
            retries += 1
            Thread.sleep(forTimeInterval: lazyTreeRetryDelay)
            let retry = HintScopeScan.run(application: application, screens: screens, budget: budget)
            if retry.sawWebArea || retry.targets.count >= result.targets.count { result = retry }
        }
        return result
    }
}

/// One pass over the Hint Scope: an open menu alone when one is showing,
/// otherwise the focused window, its sheets and popovers, and the top-level
/// menu bar items.
private enum HintScopeScan {
    private static let windowLikeRoles: Set<String> = ["AXWindow", "AXSheet", "AXPopover"]
    private static let attachedWindowRoles: Set<String> = ["AXSheet", "AXPopover"]

    static func run(application: AXUIElement, screens: [CGRect], budget: HintScanBudget) -> HintScanResult {
        let reader = AXHintTreeReader(budget: budget)
        var walk = HintTreeWalk(reader: reader)
        let values = AXHintAttributes.copy(application, [
            kAXFocusedWindowAttribute, kAXMainWindowAttribute, kAXWindowsAttribute,
            kAXMenuBarAttribute, kAXChildrenAttribute,
        ], budget: budget)
        let focused = values[0].flatMap(AXHintAttributes.element)
        let main = values[1].flatMap(AXHintAttributes.element)
        let windows = values[2].map(AXHintAttributes.elements) ?? []
        let menuBar = values[3].flatMap(AXHintAttributes.element)
        let children = values[4].map(AXHintAttributes.elements) ?? []

        let menuBarItems = menuBar.map { bar in
            reader.childElements(of: bar).compactMap { item in reader.info(of: item).map { (item, $0) } }
        } ?? []
        let openMenus = openMenus(
            menuBarItems: menuBarItems,
            applicationChildren: children.filter { child in
                !windows.contains { CFEqual($0.element, child.element) }
                    && menuBar.map { !CFEqual($0.element, child.element) } ?? true
            },
            reader: reader
        )
        if !openMenus.isEmpty {
            for (menu, info) in openMenus { walk.walk(menu, info: info, clip: .infinite) }
        } else {
            for (window, info) in roots(focused: focused, main: main, windows: windows, reader: reader) {
                walk.walk(window, info: info, clip: info.frame ?? .infinite)
            }
            for (item, info) in menuBarItems { walk.walk(item, info: info, clip: .infinite) }
        }
        let targets = HintScanRules.finalize(walk.candidates, screens: screens).map { candidate in
            HintTarget(
                element: candidate.element,
                frame: candidate.frame,
                role: candidate.info.role,
                subrole: candidate.info.subrole
            )
        }
        return HintScanResult(targets: targets, sawWebArea: walk.sawWebArea, visits: walk.visits)
    }

    private static func openMenus(
        menuBarItems: [(AXElementBox, HintNodeInfo)],
        applicationChildren: [AXElementBox],
        reader: AXHintTreeReader
    ) -> [(AXElementBox, HintNodeInfo)] {
        let contextMenus = applicationChildren.compactMap { child in
            reader.info(of: child).map { (child, $0) }
        }.filter { $0.1.role == "AXMenu" }
        let menuBarMenus = menuBarItems.filter { $0.1.selected == true }.flatMap { item, _ in
            reader.childElements(of: item).compactMap { menu in reader.info(of: menu).map { (menu, $0) } }
        }.filter { $0.1.role == "AXMenu" }
        return menuBarMenus + contextMenus
    }

    /// AXFocusedWindow can name the application itself, so the first window-like
    /// element of focused, main and listed windows is the window root.
    private static func roots(
        focused: AXElementBox?,
        main: AXElementBox?,
        windows: [AXElementBox],
        reader: AXHintTreeReader
    ) -> [(AXElementBox, HintNodeInfo)] {
        var roots: [(AXElementBox, HintNodeInfo)] = []
        func add(_ element: AXElementBox, info: HintNodeInfo) {
            guard !roots.contains(where: { CFEqual($0.0.element, element.element) }) else { return }
            roots.append((element, info))
        }
        var windowInfos: [(AXElementBox, HintNodeInfo)] = []
        for window in windows {
            if let info = reader.info(of: window) { windowInfos.append((window, info)) }
        }
        let primary = [focused, main].compactMap { $0 }.lazy.compactMap { element in
            reader.info(of: element).map { (element, $0) }
        }.first { windowLikeRoles.contains($0.1.role) }
            ?? windowInfos.first { $0.1.role == "AXWindow" }
        if let primary { add(primary.0, info: primary.1) }
        for (window, info) in windowInfos
        where attachedWindowRoles.contains(info.role) || info.subrole.map(attachedWindowRoles.contains) == true {
            add(window, info: info)
        }
        return roots
    }
}

/// The scan's shared deadline. Each AX call gets at most `perCallTimeout`,
/// capped by what remains. Confined to the scan queue.
final class HintScanBudget: @unchecked Sendable {
    static let perCallTimeout: Double = 0.2

    private let deadline: ContinuousClock.Instant

    init(duration: Duration) {
        deadline = .now.advanced(by: duration)
    }

    var remainingSeconds: Double {
        let parts = ContinuousClock.now.duration(to: deadline).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    var isExhausted: Bool { remainingSeconds <= 0 }

    func prepare(_ element: AXUIElement) -> Bool {
        let remaining = remainingSeconds
        guard remaining > 0 else { return false }
        AXUIElementSetMessagingTimeout(element, Float(min(Self.perCallTimeout, remaining)))
        return true
    }
}

struct AXHintTreeReader: HintTreeReading, @unchecked Sendable {
    private static let nodeAttributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute,
        kAXEnabledAttribute, kAXHiddenAttribute, kAXSelectedAttribute,
    ]
    private static let rowContainers: Set<String> = ["AXList", "AXTable", "AXOutline"]

    let budget: HintScanBudget

    var isExhausted: Bool { budget.isExhausted }

    func info(of element: AXElementBox) -> HintNodeInfo? {
        let values = AXHintAttributes.copy(element.element, Self.nodeAttributes, budget: budget)
        guard let role = values[0] as? String else { return nil }
        let frame: CGRect? = {
            guard let origin = values[2].flatMap(AXHintAttributes.point),
                  let size = values[3].flatMap(AXHintAttributes.size) else { return nil }
            return CGRect(origin: origin, size: size)
        }()
        return HintNodeInfo(
            role: role,
            subrole: values[1] as? String,
            frame: frame,
            enabled: values[4] as? Bool,
            hidden: values[5] as? Bool,
            selected: values[6] as? Bool
        )
    }

    func children(of element: AXElementBox, info: HintNodeInfo) -> [AXElementBox] {
        if Self.rowContainers.contains(info.role) {
            let rows = AXHintAttributes.copy(element.element, [kAXVisibleRowsAttribute], budget: budget)[0]
                .map(AXHintAttributes.elements) ?? []
            if !rows.isEmpty { return rows }
            return childElements(of: element)
        }
        let values = AXHintAttributes.copy(element.element, [kAXVisibleChildrenAttribute, kAXChildrenAttribute], budget: budget)
        let visible = values[0].map(AXHintAttributes.elements) ?? []
        return visible.isEmpty ? values[1].map(AXHintAttributes.elements) ?? [] : visible
    }

    func childElements(of element: AXElementBox) -> [AXElementBox] {
        AXHintAttributes.copy(element.element, [kAXChildrenAttribute], budget: budget)[0]
            .map(AXHintAttributes.elements) ?? []
    }
}

enum AXHintAttributes {
    /// One slot per name; nil where the value is missing or failed.
    static func copy(_ element: AXUIElement, _ names: [String], budget: HintScanBudget) -> [CFTypeRef?] {
        let missing = [CFTypeRef?](repeating: nil, count: names.count)
        guard budget.prepare(element) else { return missing }
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values
        )
        // Some elements reject one attribute outright, failing the whole batch.
        if error == .illegalArgument { return copyEach(element, names, budget: budget) }
        guard error == .success, let array = values as? [AnyObject], array.count == names.count else { return missing }
        return array.map(usable)
    }

    private static func copyEach(_ element: AXUIElement, _ names: [String], budget: HintScanBudget) -> [CFTypeRef?] {
        var unreachable = false
        return names.map { name in
            guard !unreachable, budget.prepare(element) else { return nil }
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            unreachable = error == .invalidUIElement || error == .cannotComplete
            return error == .success ? value.flatMap(usable) : nil
        }
    }

    private static func usable(_ value: AnyObject) -> CFTypeRef? {
        if value is NSNull { return nil }
        if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { return nil }
        return value
    }

    static func element(_ value: CFTypeRef) -> AXElementBox? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElementBox(element: value as! AXUIElement)
    }

    static func elements(_ value: CFTypeRef) -> [AXElementBox] {
        guard let array = value as? [AnyObject] else { return [] }
        return array.compactMap { element($0) }
    }

    static func point(_ value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
