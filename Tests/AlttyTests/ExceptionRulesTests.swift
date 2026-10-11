import AppKit
import Testing
@testable import Altty

@MainActor
struct ExceptionRulesTests {
    @Test func recommendedRemoteRulesOnlyPassThroughWhenFullscreenAndNeverHideWindows() {
        let policy = ExceptionPolicy(rules: ExceptionRule.defaults)
        for identifier in ["com.apple.ScreenSharing", "com.microsoft.rdc.macos",
            "com.teamviewer.TeamViewer", "org.virtualbox.app.VirtualBoxVM", "com.parallels.desktop.console",
            "com.citrix.XenAppViewer", "com.citrix.receiver.icaviewer.mac", "com.nicesoftware.dcvviewer",
            "com.vmware.fusion", "com.utmapp.UTM"] {
            #expect(!policy.disposition(for: identifier).hidesWindows)
            #expect(policy.shortcutsShouldBeEnabled(in: .init(bundleIdentifier: identifier, windowIsFullscreen: true)) == false)
            #expect(policy.shortcutsShouldBeEnabled(in: .init(bundleIdentifier: identifier, windowIsFullscreen: false)) == true)
        }
        #expect(policy.disposition(for: "com.parallelsOther.app") == .none)
        #expect(policy.disposition(for: "com.utmapp.UTM.other") == .none)
        #expect(policy.disposition(for: "com.apple.finder") == .none)
        #expect(policy.disposition(for: "com.McAfee.McAfeeSafariHost") == .init(hidesWindows: true, ignore: .none))
    }

    @Test func defaultsSeedFreshSettingsButNeverReplaceSavedRulesOrRestoreDeletedRules() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileSettingsPersistenceAdapter(settingsURL: directory.appending(path: "settings.json"))
        #expect(persistence.loadSettings().snapshot.exceptionRules == ExceptionRule.defaults)
        let edited = [try #require(ExceptionRule(bundleIdentifier: "com.utmapp.UTM",
            matchType: .exact, hide: true, ignore: .none))]
        for rules in [edited, []] {
            try persistence.saveSettings(SettingsSnapshot(shortcuts: .defaults, exceptionRules: rules))
            #expect(persistence.loadSettings().snapshot.exceptionRules == rules)
        }
    }

    @Test func exactAndPrefixRulesCombineByUnionAndStrongestIgnoreRegardlessOfOrder() throws {
        let prefix = try #require(ExceptionRule(
            bundleIdentifier: "com.example.",
            matchType: .prefix,
            hide: true,
            ignore: .whenFullscreen
        ))
        let exact = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Game",
            matchType: .exact,
            hide: false,
            ignore: .always
        ))

        let forward = ExceptionPolicy(rules: [prefix, exact])
            .disposition(for: "com.example.Game")
        let reversed = ExceptionPolicy(rules: [exact, prefix])
            .disposition(for: "com.example.Game")

        #expect(forward == ExceptionDisposition(hidesWindows: true, ignore: .always))
        #expect(reversed == forward)
        #expect(ExceptionPolicy(rules: [prefix]).disposition(
            for: "com.examples.Game"
        ) == .none)
    }

    @Test func ignoreConditionRequiresTheMatchingFrontmostApplicationAndFullscreenWhenConfigured() throws {
        let rule = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Streamer",
            matchType: .exact,
            hide: false,
            ignore: .whenFullscreen
        ))
        let policy = ExceptionPolicy(rules: [rule])

        #expect(policy.shortcutsShouldBeEnabled(in: ExceptionForegroundContext(
            bundleIdentifier: "com.example.Other",
            windowIsFullscreen: true
        )) == true)
        #expect(policy.shortcutsShouldBeEnabled(in: ExceptionForegroundContext(
            bundleIdentifier: "com.example.Streamer",
            windowIsFullscreen: false
        )) == true)
        #expect(policy.shortcutsShouldBeEnabled(in: ExceptionForegroundContext(
            bundleIdentifier: "com.example.Streamer",
            windowIsFullscreen: true
        )) == false)
    }

    @Test func emptyIdentifiersAreRejectedAndExactAndPrefixIdentitiesRemainDistinct() throws {
        #expect(ExceptionRule(
            bundleIdentifier: "   ",
            matchType: .exact,
            hide: true,
            ignore: .none
        ) == nil)

        let exact = try #require(ExceptionRule(
            bundleIdentifier: "com.example.App",
            matchType: .exact,
            hide: true,
            ignore: .none
        ))
        let prefix = try #require(ExceptionRule(
            bundleIdentifier: "com.example.App",
            matchType: .prefix,
            hide: false,
            ignore: .always
        ))

        #expect(exact.identity != prefix.identity)
        #expect(ExceptionRule.replacingDuplicateIdentity(in: [exact], with: exact) == [exact])
        #expect(ExceptionRule.replacingDuplicateIdentity(in: [exact], with: prefix) == [exact, prefix])
    }

    @Test func hideRemovesEveryMatchingWindowFromBothSwitcherModes() async throws {
        let rule = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Hidden",
            matchType: .exact,
            hide: true,
            ignore: .none
        ))
        let engine = SwitcherEngine(exceptionRules: [rule])
        let identities = await populate(
            engine,
            windows: [(10, 100), (11, 100), (20, 200), (21, 200)],
            applications: [
                application(pid: 100, bundleIdentifier: "com.example.Hidden", isFrontmost: true),
                application(pid: 200, bundleIdentifier: "com.example.Visible", isFrontmost: false),
            ],
            focusedIndex: 0
        )

        #expect(await engine.beginSwitch(mode: .allWindows, direction: .forward) == [
            .scheduleSwitcherPanel(delayMilliseconds: 100),
        ])
        #expect(engine.activeSwitchSession?.candidates.map(\.identity) == [
            identities[2], identities[3],
        ])
        _ = engine.receiveSession(.cancel(.escape))

        #expect(await engine.beginSwitch(mode: .currentApp, direction: .forward) == [])
        #expect(engine.activeSwitchSession == nil)
    }

    @Test func ignoreRecomputesWhenTheFrontmostWindowEntersAndLeavesFullscreen() async throws {
        let rule = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Streamer",
            matchType: .exact,
            hide: false,
            ignore: .whenFullscreen
        ))
        let engine = SwitcherEngine(exceptionRules: [rule])
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))
        let identities = await populate(
            engine,
            windows: [(10, 100)],
            applications: [
                application(pid: 100, bundleIdentifier: "com.example.Streamer", isFrontmost: true),
            ],
            focusedIndex: 0
        )

        #expect(await engine.receiveInventory(.semanticsChanged(
            identities[0],
            semanticPatch(fullscreen: true)
        )) == [.setShortcutsEnabled(false)])
        #expect(await engine.receiveInventory(.semanticsChanged(
            identities[0],
            semanticPatch(fullscreen: false)
        )) == [.setShortcutsEnabled(true)])
    }

    @Test func alwaysIgnoreRecomputesWhenTheFrontmostApplicationChanges() async throws {
        let rule = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Streamer",
            matchType: .exact,
            hide: false,
            ignore: .always
        ))
        let engine = SwitcherEngine(exceptionRules: [rule])
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))
        _ = await populate(
            engine,
            windows: [(10, 100), (20, 200)],
            applications: [
                application(pid: 100, bundleIdentifier: "com.example.Streamer", isFrontmost: true),
                application(pid: 200, bundleIdentifier: "com.example.Editor", isFrontmost: false),
            ],
            focusedIndex: 0
        )

        #expect(await engine.receiveInventory(
            .workspaceChanged(.activated(pid: 200))
        ) == [.setShortcutsEnabled(true)])
        #expect(await engine.receiveInventory(
            .workspaceChanged(.activated(pid: 100))
        ) == [.setShortcutsEnabled(false)])
    }

    @Test func readinessDoesNotCaptureAFullscreenConditionalChordBeforeFullscreenIsKnown() async throws {
        let rule = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Streamer",
            matchType: .exact,
            hide: false,
            ignore: .whenFullscreen
        ))
        let engine = SwitcherEngine(exceptionRules: [rule])
        _ = engine.updateFrontmostApplication("com.example.Streamer")
        _ = engine.receive(.accessibilityChanged(.available))

        #expect(engine.receive(.windowServerChanged(.available)) == [
            .startInventoryObservation,
            .refreshInventory(.replace),
            .recordDiagnostic(.skyLightAvailable),
        ])
    }

    @Test func fullscreenIgnoreStaysDisabledWhileAFrontmostTransitionIsUnresolved() async throws {
        let rule = try #require(ExceptionRule(
            bundleIdentifier: "com.example.",
            matchType: .prefix,
            hide: false,
            ignore: .whenFullscreen
        ))
        let engine = SwitcherEngine(exceptionRules: [rule])
        _ = engine.receive(.accessibilityChanged(.available))
        _ = engine.receive(.windowServerChanged(.available))
        let identities = await populate(
            engine,
            windows: [(10, 100), (20, 200)],
            applications: [
                application(pid: 100, bundleIdentifier: "com.example.First", isFrontmost: true),
                application(pid: 200, bundleIdentifier: "com.example.Second", isFrontmost: false),
            ],
            focusedIndex: 0
        )
        #expect(await engine.receiveInventory(.semanticsChanged(
            identities[0],
            semanticPatch(fullscreen: true)
        )) == [.setShortcutsEnabled(false)])

        #expect(await engine.receiveInventory(
            .workspaceChanged(.activated(pid: 200))
        ) == [])
        #expect(await engine.receiveInventory(.focused(identities[1])) == [
            .setShortcutsEnabled(true),
        ])
    }

    @Test func settingsRoundTripPersistsRulesAndMalformedPeersDoNotEraseValidRules() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(path: "settings.json")
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let valid = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Valid",
            matchType: .exact,
            hide: true,
            ignore: .whenFullscreen
        ))

        let snapshot = SettingsSnapshot(shortcuts: .defaults, exceptionRules: [valid])
        try persistence.saveSettings(snapshot)
        #expect(persistence.loadSettings() == SettingsLoadResult(
            snapshot: snapshot,
            warning: nil
        ))

        let mixedJSON = """
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
          "exceptionRules": [
            {
              "bundleIdentifier": "com.example.Valid",
              "matchType": "exact",
              "hide": true,
              "ignore": "whenFullscreen"
            },
            {
              "bundleIdentifier": "",
              "matchType": "exact",
              "hide": true,
              "ignore": "none"
            },
            {
              "bundleIdentifier": "com.example.Broken",
              "matchType": "title",
              "hide": false,
              "ignore": "always"
            }
          ]
        }
        """
        try Data(mixedJSON.utf8).write(to: url)

        #expect(persistence.loadSettings() == SettingsLoadResult(
            snapshot: snapshot,
            warning: .invalidExceptionRules(discardedCount: 2)
        ))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func versionOneSettingsMigrateToAnEmptyExceptionList() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = directory.appending(path: "settings.json")
        let persistence = FileSettingsPersistenceAdapter(settingsURL: url)
        let versionOneJSON = """
        {
          "version": 1,
          "shortcuts": {
            "allWindows": {
              "key": { "keyCode": 48, "displayName": "Tab" },
              "modifiers": 1
            },
            "currentApp": {
              "key": { "keyCode": 50, "displayName": "`" },
              "modifiers": 1
            }
          }
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(versionOneJSON.utf8).write(to: url)

        #expect(persistence.loadSettings() == SettingsLoadResult(
            snapshot: SettingsSnapshot(shortcuts: .defaults, exceptionRules: []),
            warning: nil
        ))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func exceptionEditsReplaceTheWholeValidatedSnapshotAfterTheActiveSessionEnds() async throws {
        let existing = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Hidden",
            matchType: .exact,
            hide: false,
            ignore: .none
        ))
        let replacement = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Hidden",
            matchType: .exact,
            hide: true,
            ignore: .always
        ))
        let engine = SwitcherEngine(exceptionRules: [existing])
        _ = await populate(
            engine,
            windows: [(10, 100), (20, 200)],
            applications: [
                application(pid: 100, bundleIdentifier: "com.example.Hidden", isFrontmost: true),
                application(pid: 200, bundleIdentifier: "com.example.Visible", isFrontmost: false),
            ],
            focusedIndex: 0
        )
        _ = await engine.beginSwitch(mode: .allWindows, direction: .forward)

        #expect(engine.send(.replaceExceptionRules([existing, replacement])) == [])
        #expect(engine.presentationState.exceptionSettings.current == [existing])
        #expect(engine.presentationState.exceptionSettings.pending == [replacement])
        let proposed = SettingsSnapshot(
            shortcuts: .defaults,
            exceptionRules: [replacement]
        )
        #expect(engine.receiveSession(.cancel(.escape)) == [
            .endActiveSession,
            .persistSettings(proposed),
        ])
        #expect(engine.receiveSettingsPersistence(.saved(proposed)) == [])
        #expect(engine.presentationState.exceptionSettings.current == [replacement])
        #expect(engine.presentationState.exceptionSettings.pending == nil)
    }

    @Test func failedExceptionReplacementPreservesTheCompletePriorSettingsSnapshot() throws {
        let existing = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Existing",
            matchType: .exact,
            hide: true,
            ignore: .none
        ))
        let proposedRule = try #require(ExceptionRule(
            bundleIdentifier: "com.example.New",
            matchType: .prefix,
            hide: false,
            ignore: .always
        ))
        let engine = SwitcherEngine(exceptionRules: [existing])
        let proposed = SettingsSnapshot(
            shortcuts: .defaults,
            exceptionRules: [existing, proposedRule]
        )

        #expect(engine.send(.replaceExceptionRules(proposed.exceptionRules)) == [
            .persistSettings(proposed),
        ])
        #expect(engine.receiveSettingsPersistence(.failed(proposed)) == [])
        #expect(engine.presentationState.exceptionSettings.current == [existing])
        #expect(engine.presentationState.exceptionSettings.pending == nil)
        #expect(engine.presentationState.exceptionSettings.inlineMessage != nil)
    }

    @Test func exceptionsSettingsShowsMissingRulesAndRoutesDeleteAndReorderActions() throws {
        let exact = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Missing",
            matchType: .exact,
            hide: true,
            ignore: .none
        ))
        let prefix = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Family",
            matchType: .prefix,
            hide: false,
            ignore: .always
        ))
        var replacements: [[ExceptionRule]] = []
        let controller = ExceptionsSettingsViewController(
            applications: FakeExceptionsAdapter(installed: [
                prefix.bundleIdentifier: ExceptionApplication(
                    bundleIdentifier: prefix.bundleIdentifier,
                    name: "Family App",
                    bundlePath: nil
                ),
            ])
        ) { replacements.append($0) }
        controller.update(ExceptionSettingsState(
            current: [exact, prefix],
            pending: nil,
            error: nil,
            recoveryWarning: nil
        ))
        let table = try #require(descendants(of: controller.view)
            .compactMap { $0 as? NSTableView }
            .first)
        let firstRow = try #require(controller.tableView(
            table,
            viewFor: table.tableColumns.first,
            row: 0
        ))
        let rowText = descendants(of: firstRow)
            .compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(rowText.contains("Missing Application"))
        #expect(rowText.contains(exact.bundleIdentifier))
        #expect(rowText.contains(exact.matchType.title))
        #expect(rowText.contains(exact.summary))
        let secondRow = try #require(controller.tableView(
            table,
            viewFor: table.tableColumns.first,
            row: 1
        ))
        let secondRowText = descendants(of: secondRow)
            .compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(secondRowText.contains("Family App"))

        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let moveUp = try #require(descendants(of: controller.view)
            .compactMap { $0 as? NSButton }
            .first { $0.title == "Move Up" })
        moveUp.performClick(nil)
        #expect(replacements.last == [prefix, exact])

        controller.update(ExceptionSettingsState(
            current: [prefix, exact],
            pending: nil,
            error: nil,
            recoveryWarning: nil
        ))
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let delete = try #require(descendants(of: controller.view)
            .compactMap { $0 as? NSButton }
            .first { $0.title == "Delete" })
        delete.performClick(nil)
        #expect(replacements.last == [exact])
    }

    @Test func exceptionsSettingsAddOpensDuplicatesAndEditRoutesTheExistingRule() throws {
        let existing = try #require(ExceptionRule(
            bundleIdentifier: "com.example.Existing",
            matchType: .exact,
            hide: false,
            ignore: .whenFullscreen
        ))
        let prefix = try #require(ExceptionRule(
            bundleIdentifier: "com.example.",
            matchType: .prefix,
            hide: true,
            ignore: .none
        ))
        let duplicateDraft = try #require(ExceptionRule(
            bundleIdentifier: existing.bundleIdentifier,
            matchType: .exact,
            hide: true,
            ignore: .none
        ))
        let editedExisting = try #require(ExceptionRule(
            bundleIdentifier: existing.bundleIdentifier,
            matchType: .exact,
            hide: true,
            ignore: .always
        ))
        let editedPrefix = try #require(ExceptionRule(
            bundleIdentifier: prefix.bundleIdentifier,
            matchType: .prefix,
            hide: false,
            ignore: .always
        ))
        var editorInitials: [ExceptionRule?] = []
        var editorMatchTypes: [ExceptionMatchType] = []
        var editorResults = [duplicateDraft, editedExisting, editedPrefix]
        var replacements: [[ExceptionRule]] = []
        let controller = ExceptionsSettingsViewController(
            applications: FakeExceptionsAdapter(),
            ruleEditor: { initial, _, matchType in
                editorInitials.append(initial)
                editorMatchTypes.append(matchType)
                return editorResults.removeFirst()
            }
        ) { replacements.append($0) }
        controller.update(ExceptionSettingsState(
            current: [existing, prefix],
            pending: nil,
            error: nil,
            recoveryWarning: nil
        ))

        let add = try #require(descendants(of: controller.view)
            .compactMap { $0 as? NSPopUpButton }
            .first)
        add.selectItem(at: 3)
        controller.addException(add)
        #expect(editorInitials.count == 2)
        #expect(editorInitials[0] == nil)
        #expect(editorInitials[1] == existing)
        #expect(editorMatchTypes[0] == .exact)
        #expect(replacements.last == [editedExisting, prefix])

        controller.update(ExceptionSettingsState(
            current: [editedExisting, prefix],
            pending: nil,
            error: nil,
            recoveryWarning: nil
        ))
        let table = try #require(descendants(of: controller.view)
            .compactMap { $0 as? NSTableView }
            .first)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let edit = try #require(descendants(of: controller.view)
            .compactMap { $0 as? NSButton }
            .first { $0.title == "Edit…" })
        edit.performClick(nil)
        #expect(editorInitials.last == prefix)
        #expect(replacements.last == [editedExisting, editedPrefix])
    }

    private func populate(
        _ engine: SwitcherEngine,
        windows: [(WindowID, ProcessID)],
        applications: [WorkspaceApplicationFacts],
        focusedIndex: Int
    ) async -> [WindowIdentity] {
        let identities = windows.map {
            WindowIdentity(wid: $0.0, pid: $0.1, generation: 1)
        }
        _ = await engine.receiveInventory(.replaceActiveSpace(WindowServerSnapshot(
            activeSpaceIDs: [1],
            windows: windows.enumerated().map { index, window in
                WindowServerWindow(
                    wid: window.0,
                    pid: window.1,
                    frontToBackOrder: index
                )
            }
        )))
        for identity in identities {
            _ = await engine.receiveInventory(.semanticsChanged(
                identity,
                semanticPatch(fullscreen: false)
            ))
        }
        _ = await engine.receiveInventory(.workspaceChanged(.snapshot(applications)))
        _ = await engine.receiveInventory(.focused(identities[focusedIndex]))
        return identities
    }

    private func application(
        pid: ProcessID,
        bundleIdentifier: String,
        isFrontmost: Bool
    ) -> WorkspaceApplicationFacts {
        WorkspaceApplicationFacts(
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            isHidden: false,
            isFrontmost: isFrontmost
        )
    }

    private func semanticPatch(fullscreen: Bool) -> WindowSemanticPatch {
        WindowSemanticPatch(
            title: .value("Window"),
            role: .value("AXWindow"),
            subrole: .value("AXStandardWindow"),
            isMinimized: .value(false),
            isFullscreen: .value(fullscreen),
            isTransient: .value(false)
        )
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }
}

@MainActor
private final class FakeExceptionsAdapter: ExceptionsAdapter {
    private let installed: [String: ExceptionApplication]

    init(installed: [String: ExceptionApplication] = [:]) {
        self.installed = installed
    }

    func runningExceptionApplications() -> [ExceptionApplication] { [] }
    func exceptionApplication(bundleIdentifier: String) -> ExceptionApplication? {
        installed[bundleIdentifier]
    }
    func exceptionApplication(at bundleURL: URL) -> ExceptionApplication? { nil }
    func frontmostApplicationBundleIdentifier() -> String? { nil }
}
