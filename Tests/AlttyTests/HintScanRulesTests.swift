import Foundation
import CoreGraphics
import Testing
@testable import Altty

private final class FakeTree: HintTreeReading {
    var infos: [Int: HintNodeInfo] = [:]
    var childrenByNode: [Int: [Int]] = [:]
    var childReads: [Int] = []
    var isExhausted = false
    private var nextID = 0

    @discardableResult
    func node(_ info: HintNodeInfo, under parent: Int? = nil) -> Int {
        let id = nextID
        nextID += 1
        infos[id] = info
        if let parent { childrenByNode[parent, default: []].append(id) }
        return id
    }

    func info(of element: Int) -> HintNodeInfo? { infos[element] }

    func children(of element: Int, info: HintNodeInfo) -> [Int] {
        childReads.append(element)
        return childrenByNode[element] ?? []
    }

    func walk(_ root: Int, clip: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 1000)) -> HintTreeWalk<FakeTree> {
        var walk = HintTreeWalk(reader: self)
        walk.walk(root, clip: clip)
        return walk
    }
}

private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 20, _ height: CGFloat = 20) -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
}

struct HintScanRulesTests {
    @Test func theAllowlistMatchesRoleOrSubroleAndRequiresEnabled() {
        #expect(HintScanRules.isClickable(HintNodeInfo(role: "AXButton", frame: nil)))
        #expect(HintScanRules.isClickable(HintNodeInfo(role: "AXRadioButton", subrole: "AXTabButton", frame: nil)))
        #expect(HintScanRules.isClickable(HintNodeInfo(role: "AXCustom", subrole: "AXSwitch", frame: nil)))
        #expect(HintScanRules.isClickable(HintNodeInfo(role: "AXRow", frame: nil, enabled: true)))
        #expect(!HintScanRules.isClickable(HintNodeInfo(role: "AXButton", frame: nil, enabled: false)))
        #expect(!HintScanRules.isClickable(HintNodeInfo(role: "AXGroup", frame: nil)))
        #expect(!HintScanRules.isClickable(HintNodeInfo(role: "AXStaticText", frame: nil)))
    }

    @Test func scrollAreasClipTheirDescendantsAndNestedAreasIntersect() {
        let tree = FakeTree()
        let window = tree.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 500, 500)))
        let outer = tree.node(HintNodeInfo(role: "AXScrollArea", frame: rect(0, 100, 500, 200)), under: window)
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(10, 50)), under: outer)
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(10, 290)), under: outer)
        let inner = tree.node(HintNodeInfo(role: "AXScrollArea", frame: rect(300, 0, 100, 400)), under: outer)
        tree.node(HintNodeInfo(role: "AXCell", frame: rect(250, 150, 100, 20)), under: inner)
        tree.node(HintNodeInfo(role: "AXCell", frame: rect(320, 350)), under: inner)

        let walk = tree.walk(window, clip: rect(0, 0, 500, 500))
        #expect(walk.candidates.map(\.frame) == [rect(10, 290, 20, 10), rect(300, 150, 50, 20)])
    }

    @Test func zeroSizedAndFullyClippedNodesAreDroppedButSizelessContainersAreEntered() {
        let tree = FakeTree()
        let window = tree.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 100, 100)))
        let group = tree.node(HintNodeInfo(role: "AXGroup", frame: nil), under: window)
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(10, 10, 0, 20)), under: group)
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(200, 10)), under: group)
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(90, 90)), under: group)
        let offscreenGroup = tree.node(HintNodeInfo(role: "AXGroup", frame: rect(300, 300)), under: window)
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(10, 10)), under: offscreenGroup)

        let walk = tree.walk(window, clip: rect(0, 0, 100, 100))
        #expect(walk.candidates.map(\.frame) == [rect(90, 90, 10, 10)])
        #expect(!tree.childReads.contains(offscreenGroup))
    }

    @Test func hiddenSubtreesTextAndImagesAreNotEntered() {
        let tree = FakeTree()
        let window = tree.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 100, 100)))
        let hidden = tree.node(HintNodeInfo(role: "AXGroup", frame: rect(0, 0, 50, 50), hidden: true), under: window)
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(0, 0)), under: hidden)
        let text = tree.node(HintNodeInfo(role: "AXStaticText", frame: rect(0, 0)), under: window)
        let image = tree.node(HintNodeInfo(role: "AXImage", frame: rect(0, 0)), under: window)

        let walk = tree.walk(window)
        #expect(walk.candidates.isEmpty)
        #expect(tree.childReads == [window])
        #expect(![hidden, text, image].contains(where: tree.childReads.contains))
    }

    @Test func interactiveLeavesAreEnteredOnlyForImportantContainers() {
        let tree = FakeTree()
        let window = tree.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 500, 500)))
        let plain = tree.node(HintNodeInfo(role: "AXButton", frame: rect(0, 0)), under: window)
        tree.node(HintNodeInfo(role: "AXCheckBox", frame: rect(0, 0)), under: plain)
        let host = tree.node(HintNodeInfo(role: "AXButton", frame: rect(100, 0)), under: window)
        let popover = tree.node(HintNodeInfo(role: "AXPopover", frame: rect(100, 30, 200, 200)), under: host)
        tree.node(HintNodeInfo(role: "AXCheckBox", frame: rect(120, 50)), under: popover)
        let checkbox = tree.node(HintNodeInfo(role: "AXCheckBox", frame: rect(400, 0)), under: window)
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(400, 0)), under: checkbox)

        let walk = tree.walk(window)
        #expect(walk.candidates.map(\.info.role) == ["AXButton", "AXButton", "AXCheckBox", "AXCheckBox"])
        #expect(walk.candidates.map(\.frame.minX) == [0, 100, 120, 400])
        #expect(!tree.childReads.contains(checkbox))
    }

    @Test func popoversAndMenusEscapeTheWindowClip() {
        let tree = FakeTree()
        let window = tree.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 100, 100)))
        let button = tree.node(HintNodeInfo(role: "AXButton", frame: rect(80, 80)), under: window)
        let popover = tree.node(HintNodeInfo(role: "AXPopover", frame: rect(60, 100, 200, 200)), under: button)
        tree.node(HintNodeInfo(role: "AXCheckBox", frame: rect(150, 150)), under: popover)

        let walk = tree.walk(window, clip: rect(0, 0, 100, 100))
        #expect(walk.candidates.map(\.frame) == [rect(80, 80, 20, 20), rect(150, 150)])
    }

    @Test func menuItemsAreEnteredOnlyWhileTheirMenuIsOpen() {
        let tree = FakeTree()
        let menu = tree.node(HintNodeInfo(role: "AXMenu", frame: rect(0, 0, 200, 200)))
        let closed = tree.node(HintNodeInfo(role: "AXMenuItem", frame: rect(0, 0, 200, 20)), under: menu)
        let open = tree.node(HintNodeInfo(role: "AXMenuItem", frame: rect(0, 20, 200, 20), selected: true), under: menu)
        let submenu = tree.node(HintNodeInfo(role: "AXMenu", frame: rect(200, 20, 200, 100)), under: open)
        tree.node(HintNodeInfo(role: "AXMenuItem", frame: rect(200, 20, 200, 20)), under: submenu)
        tree.node(HintNodeInfo(role: "AXMenuItem", frame: rect(0, 40, 200, 20), enabled: false), under: menu)

        let walk = tree.walk(menu, clip: .infinite)
        #expect(walk.candidates.map(\.frame.origin) == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 20), CGPoint(x: 200, y: 20)])
        #expect(!tree.childReads.contains(closed))
        #expect(HintScanRules.descent(HintNodeInfo(role: "AXMenuBarItem", frame: nil)) == .none)
        #expect(HintScanRules.descent(HintNodeInfo(role: "AXMenuBarItem", frame: nil, selected: true)) == .children)
    }

    @Test func webAreasAreReported() {
        let tree = FakeTree()
        let window = tree.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 100, 100)))
        #expect(!tree.walk(window).sawWebArea)
        tree.node(HintNodeInfo(role: "AXWebArea", frame: rect(0, 0, 100, 100)), under: window)
        #expect(tree.walk(window).sawWebArea)
    }

    @Test func depthAndVisitCapsBoundTheWalk() {
        let deep = FakeTree()
        var parent = deep.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 100, 100)))
        let root = parent
        for _ in 0..<HintScanRules.maximumDepth {
            parent = deep.node(HintNodeInfo(role: "AXGroup", frame: nil), under: parent)
        }
        deep.node(HintNodeInfo(role: "AXButton", frame: rect(0, 0)), under: parent)
        #expect(deep.walk(root).candidates.isEmpty)

        let wide = FakeTree()
        let window = wide.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 1000, 1000)))
        for index in 0..<7000 {
            wide.node(HintNodeInfo(role: "AXButton", frame: rect(CGFloat(index % 900), CGFloat(index / 900))), under: window)
        }
        let walk = wide.walk(window)
        #expect(walk.visits == HintScanRules.maximumVisits)
        #expect(walk.candidates.count == HintScanRules.maximumVisits - 1)
    }

    @Test func anExhaustedReaderStopsReading() {
        let tree = FakeTree()
        let window = tree.node(HintNodeInfo(role: "AXWindow", frame: rect(0, 0, 100, 100)))
        tree.node(HintNodeInfo(role: "AXButton", frame: rect(0, 0)), under: window)
        tree.isExhausted = true
        let walk = tree.walk(window)
        #expect(walk.visits == 0)
        #expect(walk.candidates.isEmpty)
    }

    @Test func finalizeDedupesMidpointsKeepsOnScreenTargetsAndSortsInReadingOrder() {
        func candidate(_ id: Int, _ frame: CGRect, depth: Int = 0) -> HintCandidate<Int> {
            HintCandidate(element: id, info: HintNodeInfo(role: "AXButton", frame: frame), frame: frame, depth: depth)
        }
        let screens = [rect(0, 0, 1000, 800), rect(1000, -200, 800, 600)]
        let result = HintScanRules.finalize([
            candidate(0, rect(500, 400)),
            candidate(1, rect(10, 10)),
            candidate(2, rect(500.2, 399.9), depth: 3),
            candidate(3, rect(1200, -150)),
            candidate(4, rect(1900, 10)),
            candidate(5, rect(900, 10)),
            candidate(6, rect(495, 395, 30, 30), depth: 1),
        ], screens: screens)
        #expect(result.map(\.element) == [3, 1, 5, 2])
    }
}

struct HintAppKindTests {
    @Test func electronIsRecognisedByItsFramework() {
        let kind = HintAppKind.classify(
            bundleIdentifier: "com.microsoft.VSCode",
            frameworkNames: ["Electron Framework.framework", "Squirrel.framework"],
            hasChromiumAppModeLoader: false
        )
        #expect(kind == .electron)
    }

    @Test func chromiumIsRecognisedByItsLoaderOrBundleIdentifier() {
        #expect(HintAppKind.classify(
            bundleIdentifier: "com.example.Browser",
            frameworkNames: ["Example Framework.framework"],
            hasChromiumAppModeLoader: true
        ) == .chromium)
        for identifier in ["com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser.beta",
                           "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "company.thebrowser.Browser",
                           "org.chromium.Chromium"] {
            #expect(HintAppKind.classify(bundleIdentifier: identifier, frameworkNames: [],
                                         hasChromiumAppModeLoader: false) == .chromium)
        }
    }

    @Test func otherAppsAreLeftAlone() {
        #expect(HintAppKind.classify(bundleIdentifier: "com.apple.Safari", frameworkNames: [],
                                     hasChromiumAppModeLoader: false) == .other)
        #expect(HintAppKind.classify(bundleIdentifier: nil, frameworkNames: [],
                                     hasChromiumAppModeLoader: false) == .other)
        #expect(!HintAppKind.other.buildsTreeLazily)
        #expect(HintAppKind.electron.buildsTreeLazily && HintAppKind.chromium.buildsTreeLazily)
    }

    @Test func aMissingBundleIsOther() {
        #expect(HintAppKind.inspect(bundleURL: URL(fileURLWithPath: "/nonexistent/App.app"), bundleIdentifier: nil) == .other)
    }
}
