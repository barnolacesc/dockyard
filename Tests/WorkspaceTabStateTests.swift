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
        let tabs: [WorkspaceTab] = [.info, .agent, .terminal(terminalID), .browser(browserID)]

        let snapshot = WorkspaceTabSnapshot(
            tabs: tabs,
            terminalCount: 1,
            browserCount: 1,
            editorCount: 0,
            activeTab: .terminal(terminalID),
            browserTitles: [browserID: "localhost"],
            terminalTitles: [terminalID: "zsh"],
            editorFilePaths: [:],
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

    func testCodableRoundTripPreservesAllTabState() throws {
        let workstreamID = UUID()
        let terminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let browserID = derivedUUID(from: workstreamID, salt: "browser-1")
        let editorID = derivedUUID(from: workstreamID, salt: "editor-1")
        let tabs: [WorkspaceTab] = [.info, .agent, .terminal(terminalID), .browser(browserID), .editor(editorID)]
        let snapshot = WorkspaceTabSnapshot(
            tabs: tabs,
            terminalCount: 1,
            browserCount: 1,
            editorCount: 1,
            activeTab: .editor(editorID),
            browserTitles: [browserID: "localhost"],
            terminalTitles: [terminalID: "zsh"],
            editorFilePaths: [editorID: "Sources/App.swift"],
            runStarted: true,
            runStoppedManually: false
        )

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(WorkspaceTabSnapshot.self, from: data)

        XCTAssertEqual(restored.tabs, tabs)
        XCTAssertEqual(restored.terminalCount, 1)
        XCTAssertEqual(restored.browserCount, 1)
        XCTAssertEqual(restored.editorCount, 1)
        XCTAssertEqual(restored.activeTab, .editor(editorID))
        XCTAssertEqual(restored.browserTitles[browserID], "localhost")
        XCTAssertEqual(restored.terminalTitles[terminalID], "zsh")
        XCTAssertEqual(restored.editorFilePaths[editorID], "Sources/App.swift")
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

        WorkspaceTabSnapshotStore.save(makeSnapshot(activeTab: .info), for: newID)

        XCTAssertEqual(WorkspaceTabSnapshotStore.load(for: existingID)?.activeTab, .agent)
        XCTAssertEqual(WorkspaceTabSnapshotStore.load(for: newID)?.activeTab, .info)
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
            tabs: [.info, .agent, .terminal(liveTerminalID), .terminal(deadTerminalID), .browser(browserID)],
            terminalCount: 2,
            browserCount: 1,
            editorCount: 0,
            activeTab: .terminal(deadTerminalID),
            browserTitles: [:],
            terminalTitles: [:],
            editorFilePaths: [:],
            runStarted: false,
            runStoppedManually: false
        )

        let reconciled = snapshot.reconciled(liveSurfaceIDs: [liveTerminalID])

        XCTAssertEqual(reconciled.tabs, [.info, .agent, .terminal(liveTerminalID), .browser(browserID)])
        XCTAssertEqual(reconciled.terminalCount, 2) // count preserved for ID generation
        XCTAssertEqual(reconciled.activeTab, .agent) // fell back since dead terminal was active
    }

    func testReconcileFiltersDeadTerminalEditorCommands() {
        let workstreamID = UUID()
        let liveTerminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let deadTerminalID = derivedUUID(from: workstreamID, salt: "terminal-2")

        let snapshot = WorkspaceTabSnapshot(
            tabs: [.info, .agent, .terminal(liveTerminalID), .terminal(deadTerminalID)],
            terminalCount: 2,
            browserCount: 0,
            editorCount: 0,
            activeTab: .terminal(liveTerminalID),
            browserTitles: [:],
            terminalTitles: [:],
            editorFilePaths: [:],
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
            tabs: [.info, .agent, .terminal(terminalID)],
            terminalCount: 1,
            browserCount: 0,
            editorCount: 0,
            activeTab: .terminal(terminalID),
            browserTitles: [:],
            terminalTitles: [:],
            editorFilePaths: [:],
            runStarted: false,
            runStoppedManually: false
        )

        let reconciled = snapshot.reconciled(liveSurfaceIDs: [terminalID])

        XCTAssertEqual(reconciled.tabs, [.info, .agent, .terminal(terminalID)])
        XCTAssertEqual(reconciled.activeTab, .terminal(terminalID))
    }

    func testReconciledPreservesRunState() {
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.info, .agent],
            terminalCount: 0,
            browserCount: 0,
            editorCount: 0,
            activeTab: .agent,
            browserTitles: [:],
            terminalTitles: [:],
            editorFilePaths: [:],
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
            tabs: [.info, .agent, .browser(browserID)],
            terminalCount: 0,
            browserCount: 1,
            editorCount: 0,
            activeTab: .browser(browserID),
            browserTitles: [:],
            terminalTitles: [:],
            editorFilePaths: [:],
            runStarted: false,
            runStoppedManually: false
        )

        // Empty live surfaces - browser should still survive
        let reconciled = snapshot.reconciled(liveSurfaceIDs: [])

        XCTAssertEqual(reconciled.tabs, [.info, .agent, .browser(browserID)])
        XCTAssertEqual(reconciled.activeTab, .browser(browserID))
    }

    func testStartupStatePreservesRestoredSnapshot() {
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.info, .agent],
            terminalCount: 0,
            browserCount: 0,
            editorCount: 0,
            activeTab: .agent,
            browserTitles: [:],
            terminalTitles: [:],
            editorFilePaths: [:],
            runStarted: true,
            runStoppedManually: false
        )

        let state = startupWorkspaceTabState(
            snapshot: snapshot,
            persistedSnapshot: nil
        )

        XCTAssertEqual(state.tabs, [.info, .agent])
        XCTAssertEqual(state.activeTab, .agent)
        XCTAssertTrue(state.runStarted)
    }

    func testStartupStateUsesPersistedSnapshotWithoutMemorySnapshot() {
        let workstreamID = UUID()
        let terminalID = derivedUUID(from: workstreamID, salt: "terminal-1")
        let browserID = derivedUUID(from: workstreamID, salt: "browser-1")
        let editorID = derivedUUID(from: workstreamID, salt: "editor-1")
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.info, .agent, .terminal(terminalID), .browser(browserID), .editor(editorID)],
            terminalCount: 1,
            browserCount: 1,
            editorCount: 1,
            activeTab: .editor(editorID),
            browserTitles: [browserID: "localhost"],
            terminalTitles: [terminalID: "zsh"],
            editorFilePaths: [editorID: "Sources/App.swift"],
            runStarted: true,
            runStoppedManually: true
        )

        let state = startupWorkspaceTabState(
            snapshot: nil,
            persistedSnapshot: snapshot
        )

        XCTAssertEqual(state.tabs, [.info, .agent, .terminal(terminalID), .browser(browserID), .editor(editorID)])
        XCTAssertEqual(state.terminalCount, 1)
        XCTAssertEqual(state.browserCount, 1)
        XCTAssertEqual(state.editorCount, 1)
        XCTAssertEqual(state.activeTab, .editor(editorID))
        XCTAssertEqual(state.browserTitles[browserID], "localhost")
        XCTAssertEqual(state.terminalTitles[terminalID], "zsh")
        XCTAssertEqual(state.editorFilePaths[editorID], "Sources/App.swift")
        XCTAssertTrue(state.runStarted)
        XCTAssertTrue(state.runStoppedManually)
    }

    func testStartupStateFallsBackToInfoWhenPersistedActiveTabIsMissing() {
        let terminalID = UUID()
        let snapshot = WorkspaceTabSnapshot(
            tabs: [.info, .agent],
            terminalCount: 0,
            browserCount: 0,
            editorCount: 0,
            activeTab: .terminal(terminalID),
            browserTitles: [:],
            terminalTitles: [:],
            editorFilePaths: [:],
            runStarted: false,
            runStoppedManually: false
        )

        let state = startupWorkspaceTabState(
            snapshot: nil,
            persistedSnapshot: snapshot
        )

        XCTAssertEqual(state.tabs, [.info, .agent])
        XCTAssertEqual(state.activeTab, .info)
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
            tabs: [.info, .agent],
            terminalCount: 0,
            browserCount: 0,
            editorCount: 0,
            activeTab: activeTab,
            browserTitles: [:],
            terminalTitles: [:],
            editorFilePaths: [:],
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
        let tabs: [WorkspaceTab] = [.info, .agent, terminalA, browserB, terminalC]

        let reordered = reorderedCustomTabs(tabs, dragging: terminalC, to: terminalA)

        XCTAssertEqual(reordered, [.info, .agent, terminalC, terminalA, browserB])
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
