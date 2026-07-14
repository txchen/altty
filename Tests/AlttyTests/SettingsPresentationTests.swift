import AppKit
import Testing
@testable import Altty

@MainActor
struct SettingsPresentationTests {
    @Test func versionTwoSettingsMigrateSequentiallyToLaunchAndPresentationDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(path: "settings.json")
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let versionTwoJSON = """
        {
          "version": 2,
          "shortcuts": {
            "allWindows": {
              "key": { "keyCode": 48, "displayName": "Tab" },
              "modifiers": 1
            },
            "currentApp": {
              "key": { "keyCode": 50, "displayName": "`" },
              "modifiers": 1
            }
          },
          "exceptionRules": []
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(versionTwoJSON.utf8).write(to: url)

        #expect(persistence.loadSettings() == SettingsLoadResult(
            snapshot: .defaults,
            warning: nil
        ))
        #expect(SettingsSnapshot.currentVersion == 3)
        #expect(SettingsSnapshot.defaults.general == .defaults)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func malformedSettingsAreCopiedForDiagnosisBeforeDefaultsLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(path: "settings.json")
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let malformed = Data("{not-json".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try malformed.write(to: url)

        #expect(persistence.loadSettings().warning == .malformed)
        #expect(try Data(contentsOf: persistence.diagnosticSettingsURL) == malformed)
        #expect(try Data(contentsOf: url) == malformed)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func generalSettingsCoordinateLoginItemBeforeSavingTheCompleteSnapshot() {
        let engine = SwitcherEngine()
        let proposed = GeneralSettings(
            launchAtLogin: true,
            listPresentation: ListPresentationPreferences(
                visibleRowCount: 8,
                density: .comfortable
            )
        )
        let snapshot = SettingsSnapshot(
            shortcuts: .defaults,
            general: proposed
        )

        #expect(engine.send(.replaceGeneralSettings(proposed)) == [
            .setLaunchAtLogin(true),
        ])
        #expect(engine.presentationState.generalSettings.pending == proposed)
        #expect(engine.receiveLaunchAtLogin(.applied(true)) == [
            .persistSettings(snapshot),
        ])
        #expect(engine.receiveSettingsPersistence(.saved(snapshot)) == [])
        #expect(engine.presentationState.generalSettings.current == proposed)
        #expect(engine.presentationState.generalSettings.pending == nil)
    }

    @Test func launchAndPersistenceFailuresKeepPriorGeneralSettingsInline() {
        let proposed = GeneralSettings(
            launchAtLogin: true,
            listPresentation: .defaults
        )
        let snapshot = SettingsSnapshot(shortcuts: .defaults, general: proposed)
        let launchFailureEngine = SwitcherEngine()
        _ = launchFailureEngine.send(.replaceGeneralSettings(proposed))

        #expect(launchFailureEngine.receiveLaunchAtLogin(.failed(true)) == [])
        #expect(launchFailureEngine.presentationState.generalSettings.current == .defaults)
        #expect(launchFailureEngine.presentationState.generalSettings.pending == nil)
        #expect(launchFailureEngine.presentationState.generalSettings.inlineMessage != nil)

        let saveFailureEngine = SwitcherEngine()
        _ = saveFailureEngine.send(.replaceGeneralSettings(proposed))
        #expect(saveFailureEngine.receiveLaunchAtLogin(.applied(true)) == [
            .persistSettings(snapshot),
        ])
        #expect(saveFailureEngine.receiveSettingsPersistence(.failed(snapshot)) == [
            .setLaunchAtLogin(false),
        ])
        #expect(saveFailureEngine.presentationState.generalSettings.current == .defaults)
        #expect(saveFailureEngine.presentationState.generalSettings.inlineMessage != nil)
    }

    @Test func panelUsesInvokingWindowDisplayFallbackAndKeepsOverflowSelectionVisible() {
        _ = NSApplication.shared
        let origin = WindowIdentity(wid: 10, pid: 100, generation: 1)
        let provider = RecordingSwitcherDisplayProvider(
            pointerLocation: CGPoint(x: 4_000, y: 4_000),
            displays: [
                SwitcherDisplay(
                    identifier: "primary",
                    frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                    visibleFrame: CGRect(x: 0, y: 24, width: 1_000, height: 776),
                    windowServerFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                    isPrimary: true
                ),
                SwitcherDisplay(
                    identifier: "secondary",
                    frame: CGRect(x: 1_000, y: 0, width: 700, height: 500),
                    visibleFrame: CGRect(x: 1_000, y: 0, width: 700, height: 480),
                    windowServerFrame: CGRect(x: 1_000, y: 0, width: 700, height: 500),
                    isPrimary: false
                ),
            ],
            windowFrames: [
                origin.wid: CGRect(x: 1_100, y: 100, width: 300, height: 240),
            ]
        )
        let rows = (1...12).map { index in
            SwitcherPanelRow(
                identity: WindowIdentity(
                    wid: WindowID(index),
                    pid: ProcessID(200 + index),
                    generation: 1
                ),
                title: "A very long window title \(index) that must remain one line",
                applicationName: "A very long application name \(index)",
                applicationBundlePath: nil,
                isMinimized: false,
                applicationIsHidden: false,
                isFullscreen: false
            )
        }
        let state = SwitcherPanelState(
            mode: .allWindows,
            shortcutDescription: "⌥Tab",
            rows: rows,
            selectedIdentity: rows[10].identity,
            invokingWindowIdentity: origin,
            listPresentation: ListPresentationPreferences(
                visibleRowCount: 6,
                density: .comfortable
            )
        )
        let panel = SwitcherPanelController(displayProvider: provider)

        panel.show(state: state)

        #expect(panel.observedState.displayIdentifier == "secondary")
        #expect(provider.displays[1].visibleFrame.contains(panel.observedState.panelFrame))
        #expect(panel.observedState.visibleRowCapacity == 6)
        #expect(panel.observedState.selectedRowIsVisible)
        #expect(panel.observedState.rows.allSatisfy { $0.usesSingleLineText })
        panel.dismiss()
    }

    @Test func checkForUpdatesOnlyOpensTheLatestReleasesPageOnExplicitAction() {
        var openedURLs: [URL] = []
        let action = GitHubReleaseUpdateAction { url in
            openedURLs.append(url)
            return true
        }

        #expect(openedURLs.isEmpty)
        action.checkForUpdates()
        #expect(openedURLs == [URL(string: "https://github.com/txchen/altty/releases/latest")!])

        let engine = SwitcherEngine()
        #expect(engine.send(.openProject) == [.openProjectPage])
        #expect(engine.send(.openSupport) == [.openSupportPage])
        #expect(engine.send(.checkForUpdates) == [.checkForUpdates])
    }

    @Test func settingsExposeAllPanesInlineStateKeyboardFocusAndAboutActions() {
        _ = NSApplication.shared
        let applications = RecordingExceptionsAdapter()
        var commands: [SwitcherCommand] = []
        let controller = SettingsWindowController(
            exceptions: applications,
            productInformation: ProductInformation(
                name: "Altty",
                version: "1.2.3",
                build: "42"
            )
        ) { commands.append($0) }
        var state = SwitcherPresentationState(
            hasLaunched: true,
            accessibility: .unavailable,
            windowServer: .unavailable
        )
        state.generalSettings.recoveryWarning = "Recovered corrupt settings inline."

        controller.show(state: state)

        #expect(controller.observedState.paneTitles == [
            "General", "Shortcuts", "Exceptions", "About",
        ])
        #expect(controller.observedState.generalSettings == .defaults)
        #expect(controller.observedState.generalInlineMessage == "Recovered corrupt settings inline.")
        #expect(controller.observedState.productSummary == "Altty 1.2.3 (42)")
        #expect(controller.observedState.sidebarHasKeyboardFocus)

        let proposed = GeneralSettings(
            launchAtLogin: true,
            listPresentation: ListPresentationPreferences(
                visibleRowCount: 8,
                density: .comfortable
            )
        )
        controller.replaceGeneralSettings(proposed)
        controller.performAboutAction(.project)
        controller.performAboutAction(.support)
        controller.performAboutAction(.checkForUpdates)
        #expect(commands == [
            .replaceGeneralSettings(proposed),
            .openProject,
            .openSupport,
            .checkForUpdates,
        ])
        controller.close()
    }

    @Test func menuBarShowsStatusAndOnlyProductionLevelActions() {
        _ = NSApplication.shared
        let menu = MenuBarController { _ in }
        menu.install()
        var state = SwitcherPresentationState(
            hasLaunched: true,
            accessibility: .unavailable,
            windowServer: .available
        )
        state.generalSettings.recoveryWarning = "Recovered settings."

        menu.update(state: state)

        #expect(menu.observedState.readinessTitle == "Accessibility permission required")
        #expect(menu.observedState.showsAccessibilityAction)
        #expect(menu.observedState.actionTitles == [
            "Check Readiness",
            "Grant Accessibility Permission…",
            "Settings…",
            "Check for Updates…",
            "Quit Altty",
        ])
        #expect(!menu.observedState.actionTitles.contains { $0.contains("Exception") })
        menu.uninstall()
    }

    @Test func panelPlacementPrioritizesPointerAndUsesPrimaryWhenWindowDisplayIsUnknown() {
        _ = NSApplication.shared
        let origin = WindowIdentity(wid: 77, pid: 100, generation: 1)
        let row = SwitcherPanelRow(
            identity: origin,
            title: "Window",
            applicationName: "Application",
            applicationBundlePath: nil,
            isMinimized: false,
            applicationIsHidden: false,
            isFullscreen: false
        )
        let state = SwitcherPanelState(
            mode: .allWindows,
            shortcutDescription: "⌥Tab",
            rows: [row],
            selectedIdentity: row.identity,
            invokingWindowIdentity: origin
        )
        let displays = [
            SwitcherDisplay(
                identifier: "secondary",
                frame: CGRect(x: 800, y: 0, width: 800, height: 600),
                visibleFrame: CGRect(x: 800, y: 0, width: 800, height: 580),
                windowServerFrame: CGRect(x: 800, y: 0, width: 800, height: 600),
                isPrimary: false
            ),
            SwitcherDisplay(
                identifier: "primary",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 580),
                windowServerFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                isPrimary: true
            ),
        ]
        let pointerProvider = RecordingSwitcherDisplayProvider(
            pointerLocation: CGPoint(x: 900, y: 300),
            displays: displays,
            windowFrames: [origin.wid: CGRect(x: 50, y: 50, width: 200, height: 200)]
        )
        let pointerPanel = SwitcherPanelController(displayProvider: pointerProvider)
        pointerPanel.show(state: state)
        #expect(pointerPanel.observedState.displayIdentifier == "secondary")
        pointerPanel.dismiss()

        let primaryProvider = RecordingSwitcherDisplayProvider(
            pointerLocation: CGPoint(x: 4_000, y: 4_000),
            displays: displays,
            windowFrames: [origin.wid: CGRect(x: 3_000, y: 3_000, width: 200, height: 200)]
        )
        let primaryPanel = SwitcherPanelController(displayProvider: primaryProvider)
        primaryPanel.show(state: state)
        #expect(primaryPanel.observedState.displayIdentifier == "primary")
        primaryPanel.dismiss()
    }
}

@MainActor
private final class RecordingSwitcherDisplayProvider: SwitcherDisplayProviding {
    var pointerLocation: CGPoint
    let displays: [SwitcherDisplay]
    let windowFrames: [WindowID: CGRect]

    init(
        pointerLocation: CGPoint,
        displays: [SwitcherDisplay],
        windowFrames: [WindowID: CGRect]
    ) {
        self.pointerLocation = pointerLocation
        self.displays = displays
        self.windowFrames = windowFrames
    }

    func frame(of window: WindowIdentity) -> CGRect? { windowFrames[window.wid] }
}

@MainActor
private final class RecordingExceptionsAdapter: ExceptionsAdapter {
    func runningExceptionApplications() -> [ExceptionApplication] { [] }
    func exceptionApplication(bundleIdentifier: String) -> ExceptionApplication? { nil }
    func exceptionApplication(at bundleURL: URL) -> ExceptionApplication? { nil }
    func frontmostApplicationBundleIdentifier() -> String? { nil }
}
