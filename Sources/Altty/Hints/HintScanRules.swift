import CoreGraphics

/// The attributes a scan reads for one AX node, frame in AX global coordinates.
struct HintNodeInfo: Equatable, Sendable {
    let role: String
    let subrole: String?
    let frame: CGRect?
    let enabled: Bool?
    let hidden: Bool?
    let selected: Bool?

    init(
        role: String,
        subrole: String? = nil,
        frame: CGRect?,
        enabled: Bool? = nil,
        hidden: Bool? = nil,
        selected: Bool? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.enabled = enabled
        self.hidden = hidden
        self.selected = selected
    }
}

struct HintCandidate<Element> {
    let element: Element
    let info: HintNodeInfo
    /// The node's frame clipped to its window and enclosing scroll areas.
    let frame: CGRect
    let depth: Int
}

extension HintCandidate: Sendable where Element: Sendable {}

/// Which nodes become Hint Targets and which subtrees a scan reads, over plain
/// values so the policy is testable without Accessibility.
enum HintScanRules {
    enum Descent: Equatable {
        case none
        case children
        /// An interactive leaf is only entered when it hosts a popover, sheet,
        /// menu, list, link or button (a toolbar button with its popover).
        case childrenIfImportant
    }

    static let maximumVisits = 6000
    static let maximumDepth = 50

    static let clickableRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXComboBox", "AXCheckBox",
        "AXRadioButton", "AXSwitch", "AXToggle", "AXDisclosureTriangle", "AXLink",
        "AXTextField", "AXTextArea", "AXSlider", "AXTabButton", "AXMenuItem",
        "AXMenuBarItem", "AXCell", "AXRow",
    ]
    private static let opaqueRoles: Set<String> = ["AXStaticText", "AXImage"]
    /// Reading a closed menu's children opens it; only an open one is entered.
    private static let menuOwnerRoles: Set<String> = ["AXMenuItem", "AXMenuBarItem"]
    private static let leafRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXComboBox", "AXCheckBox",
        "AXRadioButton", "AXSwitch", "AXDisclosureTriangle", "AXLink", "AXTextField",
        "AXTextArea", "AXSlider",
    ]
    private static let leafRolesHostingContainers: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXLink", "AXComboBox",
        "AXDisclosureTriangle", "AXTextArea", "AXRadioButton",
    ]
    private static let importantContainerRoles: Set<String> = [
        "AXPopover", "AXSheet", "AXMenu", "AXList", "AXLink", "AXButton",
    ]

    static func isClickable(_ info: HintNodeInfo) -> Bool {
        guard info.enabled != false else { return false }
        return clickableRoles.contains(info.role) || info.subrole.map(clickableRoles.contains) == true
    }

    static func descent(_ info: HintNodeInfo) -> Descent {
        if info.hidden == true || opaqueRoles.contains(info.role) { return .none }
        if menuOwnerRoles.contains(info.role) { return info.selected == true ? .children : .none }
        guard leafRoles.contains(info.role) else { return .children }
        return leafRolesHostingContainers.contains(info.role) ? .childrenIfImportant : .none
    }

    static func isImportantContainer(_ info: HintNodeInfo) -> Bool {
        importantContainerRoles.contains(info.role)
    }

    /// Frames without area say nothing about their children's placement,
    /// so only a sized frame outside the clip prunes its subtree.
    static func isOutside(_ frame: CGRect?, clip: CGRect) -> Bool {
        guard let frame, hasArea(frame) else { return false }
        return !hasArea(frame.intersection(clip))
    }

    static func visibleFrame(_ frame: CGRect?, clip: CGRect) -> CGRect? {
        guard let frame, hasArea(frame) else { return nil }
        let visible = frame.intersection(clip)
        return hasArea(visible) ? visible : nil
    }

    static func childClip(for info: HintNodeInfo, clip: CGRect) -> CGRect {
        guard info.role == "AXScrollArea", let frame = info.frame, hasArea(frame) else { return clip }
        return clip.intersection(frame)
    }

    /// Keeps targets whose midpoint is on a screen, collapses targets sharing a
    /// rounded midpoint to the deepest one, and puts them in reading order.
    static func finalize<Element>(
        _ candidates: [HintCandidate<Element>],
        screens: [CGRect]
    ) -> [HintCandidate<Element>] {
        var kept: [HintCandidate<Element>] = []
        var indexByMidpoint: [Midpoint: Int] = [:]
        for candidate in candidates {
            let midpoint = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
            guard screens.contains(where: { $0.contains(midpoint) }) else { continue }
            let key = Midpoint(x: Int(midpoint.x.rounded()), y: Int(midpoint.y.rounded()))
            if let index = indexByMidpoint[key] {
                if candidate.depth > kept[index].depth { kept[index] = candidate }
                continue
            }
            indexByMidpoint[key] = kept.count
            kept.append(candidate)
        }
        return kept.enumerated().sorted { lhs, rhs in
            if HintLabels.readingOrder(lhs.element.frame, rhs.element.frame) { return true }
            if HintLabels.readingOrder(rhs.element.frame, lhs.element.frame) { return false }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private struct Midpoint: Hashable {
        let x: Int
        let y: Int
    }

    private static func hasArea(_ rect: CGRect) -> Bool {
        !rect.isNull && rect.width > 0 && rect.height > 0
    }
}

protocol HintTreeReading {
    associatedtype Element
    var isExhausted: Bool { get }
    func info(of element: Element) -> HintNodeInfo?
    func children(of element: Element, info: HintNodeInfo) -> [Element]
}

/// One depth-first pass over AX subtrees, bounded by `HintScanRules` caps
/// and the reader's deadline. Children are read before descending so an
/// interactive leaf can be checked for important containers.
struct HintTreeWalk<Reader: HintTreeReading> {
    let reader: Reader
    private(set) var candidates: [HintCandidate<Reader.Element>] = []
    private(set) var visits = 0
    private(set) var sawWebArea = false

    init(reader: Reader) {
        self.reader = reader
    }

    var isStopped: Bool { visits >= HintScanRules.maximumVisits || reader.isExhausted }

    mutating func walk(_ root: Reader.Element, clip: CGRect) {
        guard let info = read(root) else { return }
        visit(root, info: info, clip: clip, depth: 0)
    }

    private mutating func read(_ element: Reader.Element) -> HintNodeInfo? {
        guard !isStopped else { return nil }
        visits += 1
        return reader.info(of: element)
    }

    private mutating func visit(_ element: Reader.Element, info: HintNodeInfo, clip: CGRect, depth: Int) {
        guard info.hidden != true else { return }
        if info.role == "AXWebArea" { sawWebArea = true }
        guard !HintScanRules.isOutside(info.frame, clip: clip) else { return }
        if HintScanRules.isClickable(info), let frame = HintScanRules.visibleFrame(info.frame, clip: clip) {
            candidates.append(HintCandidate(element: element, info: info, frame: frame, depth: depth))
        }
        let descent = HintScanRules.descent(info)
        guard descent != .none, depth < HintScanRules.maximumDepth, !isStopped else { return }
        var children: [(Reader.Element, HintNodeInfo)] = []
        for child in reader.children(of: element, info: info) {
            if let childInfo = read(child) {
                children.append((child, childInfo))
            } else if isStopped {
                break
            }
        }
        if descent == .childrenIfImportant,
           !children.contains(where: { HintScanRules.isImportantContainer($0.1) }) {
            return
        }
        let childClip = HintScanRules.childClip(for: info, clip: clip)
        for (child, childInfo) in children {
            visit(child, info: childInfo, clip: childClip, depth: depth + 1)
        }
    }
}
