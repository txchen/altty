import Testing
@testable import Altty

struct WindowCompatibilityTests {
    @Test func floatingToolsAreNotRealSwitchTargets() {
        #expect(WindowQualification.isTransient(role: "AXWindow", subrole: "AXFloatingWindow"))
        #expect(WindowQualification.isTransient(role: "AXWindow", subrole: "AXSystemDialog"))
    }
}

extension WindowCompatibilityTests {
    @Test func windowFactsDistinguishUtilitySurfacesFromDocumentsAndSlideshows() {
        let identity = WindowIdentity(wid: 10, pid: 100, generation: 1)
        func accepts(_ level: Int, main: Bool?, subrole: String?, parent: WindowID? = nil, fullscreen: Bool = false) -> Bool {
            WindowQualification.accepts(identity: identity,
                server: .init(wid: 10, pid: 100, frontToBackOrder: 0, level: level,
                              frame: .init(x: 0, y: 0, width: 720, height: 84)),
                role: "AXWindow", subrole: subrole, isMain: main, isFullscreen: fullscreen, parent: parent)
        }
        #expect(!accepts(3, main: false, subrole: "AXDialog")) // dictation-like strip
        #expect(!accepts(3, main: false, subrole: "AXStandardWindow")) // floating utility
        #expect(!accepts(3, main: nil, subrole: "AXStandardWindow")) // not enough facts
        #expect(accepts(3, main: true, subrole: "AXStandardWindow")) // always-on-top document
        #expect(accepts(25, main: true, subrole: "AXUnknown")) // slideshow
        #expect(accepts(0, main: false, subrole: "AXUnknown")) // custom app window
        #expect(!accepts(0, main: true, subrole: "AXStandardWindow", parent: 99)) // child overlay
        #expect(accepts(3, main: false, subrole: "AXStandardWindow", fullscreen: true))
    }
}
