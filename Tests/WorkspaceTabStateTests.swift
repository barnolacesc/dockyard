// ABOUTME: Tests for workspace tab restoration and custom tab reordering.
// ABOUTME: Verifies full-fidelity tab snapshots restore and custom tabs reorder deterministically.

import AppKit
@testable import Dockyard
import XCTest

final class WorkspaceTabSnapshotTests: XCTestCase {
    private let snapshotsKey = "dockyard.workspaceTabSnapshots"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: snapshotsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: snapshotsKey)
        super.tearDown()
    }

    func testSaveAndRestore() {
        let workstreamID = UUID()
        let terminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let browserID = derivedUUID(from: workstreamID, salt: "browser-1")
        let tabs: [WorkspaceTab] = [.agent, .terminal(terminalID), .browser(browserID)]

        let snapshot = WorkspaceTabSnapshot(
            tabs: tabs,
            terminalCount: 1,
            browserCount: 1,
            activeTab: .terminal(terminalID),
            browserTitles: [browserID: "localhost"],
            terminalTitles: [terminalID: "zsh"],
            runStarted: false,
            runStoppedManually: false
        )

        XCTAssertEqual(snapshot.tabs, tabs)
        XCTAssertEqual(snapshot.terminalCount, 1)
        XCTAssertEqual(snapshot.browserCount, 1)
        XCTAssertEqual(snapshot.activeTab, .terminal(terminalID))
        XCTAssertEqual(snapshot.browserTitles[browserID], "localhost")
        XCTAssertEqual(snapshot.terminalTitles[terminalID], "zsh")
    }

    func testAgentBrowserRoundTripsAndRequiresLiveTerminalSurface() throws {
        let workstreamID = UUID()
        let agentBrowserID = derivedUUID(from: workstreamID, salt: "agent-browser-1")
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent, .agentBrowser(agentBrowserID)],
            terminalCount: 0,
            browserCount: 1,
            activeTab: .agentBrowser(agentBrowserID)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WorkspaceTabSnapshot.self, from: data)
        XCTAssertEqual(decoded.tabs, [.agent, .agentBrowser(agentBrowserID)])
        XCTAssertEqual(decoded.activeTab, .agentBrowser(agentBrowserID))

        let live = decoded.reconciled(liveSurfaceIDs: [agentBrowserID])
        XCTAssertEqual(live.tabs, [.agent, .agentBrowser(agentBrowserID)])

        let stale = decoded.reconciled(liveSurfaceIDs: [])
        XCTAssertEqual(stale.tabs, [.agent])
        XCTAssertEqual(stale.activeTab, .agent)
    }

    func testCodableRoundTripPreservesAllTabState() throws {
        let workstreamID = UUID()
        let terminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let browserID = derivedUUID(from: workstreamID, salt: "browser-1")
        let editorTerminalID = derivedUUID(from: workstreamID, salt: "editor-terminal-1")
        let tabs: [WorkspaceTab] = [.agent, .terminal(terminalID), .browser(browserID), .terminal(editorTerminalID)]
        let snapshot = WorkspaceTabSnapshot(
            tabs: tabs,
            terminalCount: 2,
            browserCount: 1,
            activeTab: .terminal(editorTerminalID),
            browserTitles: [browserID: "localhost"],
            terminalTitles: [terminalID: "zsh", editorTerminalID: "Editor"],
            runStarted: true,
            runStoppedManually: false,
            terminalEditorCommands: [editorTerminalID: "nvim ."],
            browserURLs: [browserID: "https://github.com/test"]
        )

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(WorkspaceTabSnapshot.self, from: data)

        XCTAssertEqual(restored.tabs, tabs)
        XCTAssertEqual(restored.terminalCount, 2)
        XCTAssertEqual(restored.browserCount, 1)
        XCTAssertEqual(restored.activeTab, .terminal(editorTerminalID))
        XCTAssertEqual(restored.browserTitles[browserID], "localhost")
        XCTAssertEqual(restored.terminalTitles[terminalID], "zsh")
        XCTAssertEqual(restored.terminalTitles[editorTerminalID], "Editor")
        XCTAssertEqual(restored.terminalEditorCommands[editorTerminalID], "nvim .")
        XCTAssertEqual(restored.browserURLs[browserID], "https://github.com/test")
        XCTAssertTrue(restored.runStarted)
        XCTAssertFalse(restored.runStoppedManually)
    }

    func testDecodingMixedSnapshotsPreservesOnlyValidEntries() throws {
        let validID = UUID()
        let invalidID = UUID()
        let validSnapshot = makeSnapshot(activeTab: .agent)
        let validObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(validSnapshot))
        let data = try JSONSerialization.data(withJSONObject: [
            validID.uuidString: validObject,
            invalidID.uuidString: ["tabs": "not-an-array"],
        ])

        let decoded = try XCTUnwrap(WorkspaceTabSnapshotStore.decodeSnapshots(from: data))

        XCTAssertEqual(decoded[validID.uuidString]?.activeTab, .agent)
        XCTAssertNil(decoded[invalidID.uuidString])
    }

    func testLoadRestoresValidSnapshotAtByteLimit() throws {
        let workstreamID = UUID()
        let snapshot = makeSnapshot(activeTab: .agent)
        var data = try JSONEncoder().encode([workstreamID.uuidString: snapshot])
        XCTAssertLessThan(data.count, WorkspaceTabSnapshotStore.maximumRestoreBytes)
        data.append(
            Data(
                repeating: 0x20,
                count: WorkspaceTabSnapshotStore.maximumRestoreBytes - data.count
            )
        )
        UserDefaults.standard.set(data, forKey: snapshotsKey)

        XCTAssertEqual(WorkspaceTabSnapshotStore.load(for: workstreamID)?.activeTab, .agent)
        XCTAssertEqual(UserDefaults.standard.data(forKey: snapshotsKey), data)
    }

    func testLoadRejectsOversizedSnapshotWithoutDeletingStoredBytes() throws {
        let workstreamID = UUID()
        let snapshot = makeSnapshot(activeTab: .agent)
        var data = try JSONEncoder().encode([workstreamID.uuidString: snapshot])
        XCTAssertLessThan(data.count, WorkspaceTabSnapshotStore.maximumRestoreBytes)
        data.append(
            Data(
                repeating: 0x20,
                count: WorkspaceTabSnapshotStore.maximumRestoreBytes - data.count + 1
            )
        )
        UserDefaults.standard.set(data, forKey: snapshotsKey)

        XCTAssertNil(WorkspaceTabSnapshotStore.load(for: workstreamID))
        XCTAssertEqual(UserDefaults.standard.data(forKey: snapshotsKey), data)
    }

    func testLoadRejectsMalformedSnapshotWithoutDeletingStoredBytes() {
        let workstreamID = UUID()
        let data = Data(#"{"unexpected":"array"}"#.utf8)
        UserDefaults.standard.set(data, forKey: snapshotsKey)

        XCTAssertNil(WorkspaceTabSnapshotStore.load(for: workstreamID))
        XCTAssertEqual(UserDefaults.standard.data(forKey: snapshotsKey), data)
    }

    func testSavePreservesValidSnapshotWhenAnotherEntryIsMalformed() throws {
        let existingID = UUID()
        let malformedID = UUID()
        let newID = UUID()
        let existingObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makeSnapshot(activeTab: .agent))
        )
        let data = try JSONSerialization.data(withJSONObject: [
            existingID.uuidString: existingObject,
            malformedID.uuidString: ["tabs": "not-an-array"],
        ])
        UserDefaults.standard.set(data, forKey: snapshotsKey)

        let newTerminalID = UUID()
        WorkspaceTabSnapshotStore.save(
            WorkspaceTabSnapshot(
                tabs: [.agent, .terminal(newTerminalID)],
                terminalCount: 1,
                browserCount: 0,
                activeTab: .terminal(newTerminalID),
                browserTitles: [:],
                terminalTitles: [:],
                runStarted: false,
                runStoppedManually: false
            ),
            for: newID
        )

        XCTAssertEqual(WorkspaceTabSnapshotStore.load(for: existingID)?.activeTab, .agent)
        XCTAssertEqual(WorkspaceTabSnapshotStore.load(for: newID)?.activeTab, .terminal(newTerminalID))
        XCTAssertNil(WorkspaceTabSnapshotStore.load(for: malformedID))
    }

    func testRemovePreservesValidSnapshotWhenAnotherEntryIsMalformed() throws {
        let validID = UUID()
        let malformedID = UUID()
        let validObject = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(makeSnapshot(activeTab: .agent))
        )
        let data = try JSONSerialization.data(withJSONObject: [
            validID.uuidString: validObject,
            malformedID.uuidString: ["tabs": "not-an-array"],
        ])
        UserDefaults.standard.set(data, forKey: snapshotsKey)

        WorkspaceTabSnapshotStore.remove(for: malformedID)

        XCTAssertEqual(WorkspaceTabSnapshotStore.load(for: validID)?.activeTab, .agent)
        XCTAssertNil(WorkspaceTabSnapshotStore.load(for: malformedID))
    }

    func testReconcileFiltersDeadTerminals() {
        let workstreamID = UUID()
        let liveTerminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let deadTerminalID = derivedUUID(from: workstreamID, salt: "terminal-2")
        let browserID = derivedUUID(from: workstreamID, salt: "browser-1")

        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent, .terminal(liveTerminalID), .terminal(deadTerminalID), .browser(browserID)],
            terminalCount: 2,
            browserCount: 1,
            activeTab: .terminal(deadTerminalID),
            browserTitles: [:],
            terminalTitles: [:],
            runStarted: false,
            runStoppedManually: false
        )

        let reconciled = snapshot.reconciled(liveSurfaceIDs: [liveTerminalID])

        XCTAssertEqual(reconciled.tabs, [.agent, .terminal(liveTerminalID), .browser(browserID)])
        XCTAssertEqual(reconciled.terminalCount, 2) // count preserved for ID generation
        XCTAssertEqual(reconciled.activeTab, .agent) // fell back since dead terminal was active
    }

    func testReconcileFiltersDeadTerminalEditorCommands() {
        let workstreamID = UUID()
        let liveTerminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let deadTerminalID = derivedUUID(from: workstreamID, salt: "terminal-2")

        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent, .terminal(liveTerminalID), .terminal(deadTerminalID)],
            terminalCount: 2,
            browserCount: 0,
            activeTab: .terminal(liveTerminalID),
            browserTitles: [:],
            terminalTitles: [:],
            runStarted: false,
            runStoppedManually: false,
            terminalEditorCommands: [
                liveTerminalID: "nvim .",
                deadTerminalID: "hx .",
            ]
        )

        let reconciled = snapshot.reconciled(liveSurfaceIDs: [liveTerminalID])

        XCTAssertEqual(reconciled.terminalEditorCommands, [liveTerminalID: "nvim ."])
    }

    func testReconcilePreservesActiveTabWhenAlive() {
        let workstreamID = UUID()
        let terminalID = derivedUUID(from: workstreamID, salt: "terminal-1")

        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent, .terminal(terminalID)],
            terminalCount: 1,
            browserCount: 0,
            activeTab: .terminal(terminalID),
            browserTitles: [:],
            terminalTitles: [:],
            runStarted: false,
            runStoppedManually: false
        )

        let reconciled = snapshot.reconciled(liveSurfaceIDs: [terminalID])

        XCTAssertEqual(reconciled.tabs, [.agent, .terminal(terminalID)])
        XCTAssertEqual(reconciled.activeTab, .terminal(terminalID))
    }

    func testReconciledPreservesRunState() {
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent],
            terminalCount: 0,
            browserCount: 0,
            activeTab: .agent,
            browserTitles: [:],
            terminalTitles: [:],
            runStarted: true,
            runStoppedManually: false
        )

        let reconciled = snapshot.reconciled(liveSurfaceIDs: [])

        XCTAssertTrue(reconciled.runStarted)
        XCTAssertFalse(reconciled.runStoppedManually)
    }

    func testReconcileKeepsBrowserTabsRegardlessOfSurfaces() {
        let browserID = UUID()

        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent, .browser(browserID)],
            terminalCount: 0,
            browserCount: 1,
            activeTab: .browser(browserID),
            browserTitles: [:],
            terminalTitles: [:],
            runStarted: false,
            runStoppedManually: false
        )

        // Empty live surfaces - browser should still survive
        let reconciled = snapshot.reconciled(liveSurfaceIDs: [])

        XCTAssertEqual(reconciled.tabs, [.agent, .browser(browserID)])
        XCTAssertEqual(reconciled.activeTab, .browser(browserID))
    }

    func testStartupStatePreservesRestoredSnapshot() {
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent],
            terminalCount: 0,
            browserCount: 0,
            activeTab: .agent,
            browserTitles: [:],
            terminalTitles: [:],
            runStarted: true,
            runStoppedManually: false
        )

        let state = startupWorkspaceTabState(
            snapshot: snapshot,
            persistedSnapshot: nil
        )

        XCTAssertEqual(state.tabs, [.agent])
        XCTAssertEqual(state.activeTab, .agent)
        XCTAssertTrue(state.runStarted)
    }

    func testStartupStateUsesPersistedSnapshotWithoutMemorySnapshot() {
        let workstreamID = UUID()
        let terminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let browserID = derivedUUID(from: workstreamID, salt: "browser-1")
        let editorTerminalID = derivedUUID(from: workstreamID, salt: "editor-terminal-1")
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent, .terminal(terminalID), .browser(browserID), .terminal(editorTerminalID)],
            terminalCount: 2,
            browserCount: 1,
            activeTab: .terminal(editorTerminalID),
            browserTitles: [browserID: "localhost"],
            terminalTitles: [terminalID: "zsh", editorTerminalID: "Editor"],
            runStarted: true,
            runStoppedManually: true,
            terminalEditorCommands: [editorTerminalID: "nvim ."]
        )

        let state = startupWorkspaceTabState(
            snapshot: nil,
            persistedSnapshot: snapshot
        )

        XCTAssertEqual(state.tabs, [.agent, .terminal(terminalID), .browser(browserID), .terminal(editorTerminalID)])
        XCTAssertEqual(state.terminalCount, 2)
        XCTAssertEqual(state.browserCount, 1)
        XCTAssertEqual(state.activeTab, .terminal(editorTerminalID))
        XCTAssertEqual(state.browserTitles[browserID], "localhost")
        XCTAssertEqual(state.terminalTitles[terminalID], "zsh")
        XCTAssertEqual(state.terminalTitles[editorTerminalID], "Editor")
        XCTAssertEqual(state.terminalEditorCommands[editorTerminalID], "nvim .")
        XCTAssertTrue(state.runStarted)
        XCTAssertTrue(state.runStoppedManually)
    }

    func testStartupStateFallsBackToAgentWhenPersistedActiveTabIsMissing() {
        let terminalID = UUID()
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.agent],
            terminalCount: 0,
            browserCount: 0,
            activeTab: .terminal(terminalID),
            browserTitles: [:],
            terminalTitles: [:],
            runStarted: false,
            runStoppedManually: false
        )

        let state = startupWorkspaceTabState(
            snapshot: nil,
            persistedSnapshot: snapshot
        )

        XCTAssertEqual(state.tabs, [.agent])
        XCTAssertEqual(state.activeTab, .agent)
    }

    func testLegacyEditorTabDecodingIsSafelySkipped() throws {
        let workstreamID = UUID()
        let terminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let legacyEditorID = derivedUUID(from: workstreamID, salt: "legacy-editor-1")

        // JSON matching pre-removal WorkspaceTabSnapshot with .editor tab and activeTab: .editor
        let legacyJSON = """
        {
            "tabs": [
                {"info": {}},
                {"agent": {}},
                {"editor": {"_0": "\(legacyEditorID.uuidString)"}},
                {"terminal": {"_0": "\(terminalID.uuidString)"}}
            ],
            "terminalCount": 1,
            "browserCount": 0,
            "editorCount": 1,
            "activeTab": {"editor": {"_0": "\(legacyEditorID.uuidString)"}},
            "browserTitles": [],
            "terminalTitles": ["\(terminalID.uuidString)", "zsh"],
            "editorFilePaths": ["\(legacyEditorID.uuidString)", "Sources/App.swift"],
            "runStarted": false,
            "runStoppedManually": false
        }
        """

        let data = Data(legacyJSON.utf8)
        let restored = try JSONDecoder().decode(WorkspaceTabSnapshot.self, from: data)

        // Legacy editor and info tabs should be skipped, leaving agent and terminal
        XCTAssertEqual(restored.tabs, [.agent, .terminal(terminalID)])
        // Active tab was the legacy editor tab, which was dropped, so it falls back to .agent
        XCTAssertEqual(restored.activeTab, .agent)
        XCTAssertEqual(restored.terminalTitles[terminalID], "zsh")
    }

    func testWorkspaceEnvironmentUsesSuppliedDefaultBranch() throws {
        let workstreamID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

        let vars = workspaceEnvironmentVariables(
            workstreamID: workstreamID,
            projectName: "app",
            workstreamName: "task",
            projectDirectory: "/app",
            workingDirectory: "/app/task",
            port: 3000,
            codingCLI: .claude,
            agentTeams: false,
            defaultBranch: "develop",
            scriptSource: "conductor.json"
        )

        XCTAssertEqual(vars["DY_DEFAULT_BRANCH"], "develop")
        XCTAssertEqual(vars["CONDUCTOR_DEFAULT_BRANCH"], "develop")
    }

    func testResolvedTerminalEditorCommandTrimsWhitespace() {
        XCTAssertEqual(resolvedTerminalEditorCommand("  hx .\n"), "hx .")
    }

    func testResolvedTerminalEditorCommandFallsBackForEmptyInput() {
        XCTAssertEqual(resolvedTerminalEditorCommand(""), "nvim .")
        XCTAssertEqual(resolvedTerminalEditorCommand(" \n\t "), "nvim .")
    }

    func testResolvedTerminalEditorCommandKeepsCustomCommand() {
        XCTAssertEqual(resolvedTerminalEditorCommand("vim"), "vim")
        XCTAssertEqual(resolvedTerminalEditorCommand("hx ."), "hx .")
    }

    private func makeSnapshot(activeTab: WorkspaceTab) -> WorkspaceTabSnapshot {
        WorkspaceTabSnapshot(
            tabs: [.agent],
            terminalCount: 0,
            browserCount: 0,
            activeTab: activeTab,
            browserTitles: [:],
            terminalTitles: [:],
            runStarted: false,
            runStoppedManually: false
        )
    }
}

final class WorkspaceTabStateTests: XCTestCase {
    func testCommandBracketShortcutsAreHandledBeforeTerminalInput() {
        XCTAssertEqual(
            commandKeyNotification(charactersIgnoringModifiers: "[", modifierFlags: [.command]),
            .prevWorkstream
        )
        XCTAssertEqual(
            commandKeyNotification(charactersIgnoringModifiers: "]", modifierFlags: [.command]),
            .nextWorkstream
        )
        XCTAssertEqual(
            commandKeyNotification(charactersIgnoringModifiers: "[", modifierFlags: [.command, .shift]),
            .prevTab
        )
        XCTAssertEqual(
            commandKeyNotification(charactersIgnoringModifiers: "]", modifierFlags: [.command, .shift]),
            .nextTab
        )
        XCTAssertEqual(
            commandKeyNotification(charactersIgnoringModifiers: "w", modifierFlags: [.command]),
            .closeTerminal
        )
    }

    func testCommandBracketShortcutsIgnoreOptionAndControlChords() {
        XCTAssertNil(commandKeyNotification(charactersIgnoringModifiers: "[", modifierFlags: [.command, .option]))
        XCTAssertNil(commandKeyNotification(charactersIgnoringModifiers: "[", modifierFlags: [.command, .control]))
        XCTAssertNil(commandKeyNotification(charactersIgnoringModifiers: "x", modifierFlags: [.command]))
    }

    func testReorderedCustomTabsKeepsFixedTabsInPlace() throws {
        let terminalA = try WorkspaceTab.terminal(XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")))
        let browserB = try WorkspaceTab.browser(XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")))
        let terminalC = try WorkspaceTab.terminal(XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")))
        let tabs: [WorkspaceTab] = [.agent, terminalA, browserB, terminalC]

        let reordered = reorderedCustomTabs(tabs, dragging: terminalC, to: terminalA)

        XCTAssertEqual(reordered, [.agent, terminalC, terminalA, browserB])
    }

    func testRenderableWorkstreamIDKeepsOnlySelectedReadyWorkstream() throws {
        let selectedID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let previousID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let nextID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let unreadyID = try XCTUnwrap(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"))
        let project = Project(
            name: "app",
            directory: "/app",
            workstreams: [
                Workstream(name: "selected", worktreePath: "/app/selected", id: selectedID, lastAccessedAt: Date(timeIntervalSince1970: 40)),
                Workstream(name: "previous", worktreePath: "/app/previous", id: previousID, lastAccessedAt: Date(timeIntervalSince1970: 50)),
                Workstream(name: "next", worktreePath: "/app/next", id: nextID, lastAccessedAt: Date(timeIntervalSince1970: 30)),
                Workstream(name: "unready", id: unreadyID, lastAccessedAt: Date(timeIntervalSince1970: 20)),
            ]
        )

        let id = renderableWorkstreamID(
            in: project,
            selectedWorkstreamID: selectedID,
            pathExists: { _ in true }
        )

        XCTAssertEqual(id, selectedID)
    }

    func testRenderableWorkstreamIDSkipsUnreadySelection() throws {
        let selectedID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let project = Project(
            name: "app",
            directory: "/app",
            workstreams: [
                Workstream(name: "selected", id: selectedID),
            ]
        )

        let id = renderableWorkstreamID(in: project, selectedWorkstreamID: selectedID)

        XCTAssertNil(id)
    }

    func testRenderableWorkstreamIDSkipsMissingWorktreePath() throws {
        let selectedID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let project = Project(
            name: "app",
            directory: "/app",
            workstreams: [
                Workstream(name: "selected", worktreePath: "/app/missing", id: selectedID),
            ]
        )

        let id = renderableWorkstreamID(
            in: project,
            selectedWorkstreamID: selectedID,
            pathExists: { _ in false }
        )

        XCTAssertNil(id)
    }

    func testCycleWorkstreamWrapsToPreviousExistingWorktree() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let missingID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let previousID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let project = Project(
            name: "app",
            directory: "/app",
            workstreams: [
                Workstream(name: "first", worktreePath: "/app/first", id: firstID, lastAccessedAt: Date(timeIntervalSince1970: 30)),
                Workstream(name: "missing", worktreePath: "/app/missing", id: missingID, lastAccessedAt: Date(timeIntervalSince1970: 20)),
                Workstream(name: "previous", worktreePath: "/app/previous", id: previousID, lastAccessedAt: Date(timeIntervalSince1970: 10)),
            ]
        )

        let id = cycledWorkstreamID(
            in: project,
            selectedWorkstreamID: firstID,
            direction: -1,
            pathExists: { $0 != "/app/missing" }
        )

        XCTAssertEqual(id, previousID)
    }

    func testCycleWorkstreamUsesManualOrderNotRecency() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let secondID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let project = Project(
            name: "app",
            directory: "/app",
            workstreams: [
                Workstream(name: "first", worktreePath: "/app/first", id: firstID, lastAccessedAt: Date(timeIntervalSince1970: 10)),
                Workstream(name: "second", worktreePath: "/app/second", id: secondID, lastAccessedAt: Date(timeIntervalSince1970: 30)),
            ]
        )

        let id = cycledWorkstreamID(
            in: project,
            selectedWorkstreamID: nil,
            direction: 1,
            pathExists: { _ in true }
        )

        XCTAssertEqual(id, firstID)
    }

    func testCycleGlobalWorkstreamUsesProjectAndWorkstreamManualOrder() throws {
        let oldRecentID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let firstManualID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let projects = [
            Project(
                name: "first",
                directory: "/first",
                workstreams: [
                    Workstream(name: "old-recent", worktreePath: "/first/old", id: oldRecentID, lastAccessedAt: Date(timeIntervalSince1970: 10)),
                ],
                lastAccessedAt: Date(timeIntervalSince1970: 10)
            ),
            Project(
                name: "second",
                directory: "/second",
                workstreams: [
                    Workstream(name: "new-recent", worktreePath: "/second/new", id: firstManualID, lastAccessedAt: Date(timeIntervalSince1970: 30)),
                ],
                lastAccessedAt: Date(timeIntervalSince1970: 30)
            ),
        ]

        let id = cycledGlobalWorkstreamID(
            in: projects,
            selectedWorkstreamID: nil,
            direction: 1,
            pathExists: { _ in true }
        )

        XCTAssertEqual(id, oldRecentID)
    }

    func testCycleProjectUsesManualOrderNotRecency() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let secondID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let projects = [
            Project(name: "first", directory: "/first", id: firstID, lastAccessedAt: Date(timeIntervalSince1970: 10)),
            Project(name: "second", directory: "/second", id: secondID, lastAccessedAt: Date(timeIntervalSince1970: 30)),
        ]

        let id = cycledProjectID(in: projects, selectedProjectID: nil, direction: 1)

        XCTAssertEqual(id, firstID)
    }
}

final class SidebarExpansionTests: XCTestCase {
    func testSelectionExpansionAddsSelectedProject() throws {
        let selectedProjectID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let existingProjectID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))

        let expanded = expandedProjectIDs(
            afterSelecting: .project(selectedProjectID),
            current: [existingProjectID],
            projectIDByWorkstreamID: [:]
        )

        XCTAssertEqual(expanded, [existingProjectID, selectedProjectID])
    }

    func testSelectionExpansionAddsParentProjectForWorkstream() throws {
        let workstreamID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let projectID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))

        let expanded = expandedProjectIDs(
            afterSelecting: .workstream(workstreamID),
            current: [],
            projectIDByWorkstreamID: [workstreamID: projectID]
        )

        XCTAssertEqual(expanded, [projectID])
    }

    func testSelectionExpansionIgnoresMissingWorkstreamParent() throws {
        let workstreamID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))

        let expanded = expandedProjectIDs(
            afterSelecting: .workstream(workstreamID),
            current: [],
            projectIDByWorkstreamID: [:]
        )

        XCTAssertEqual(expanded, [])
    }
}
