// ABOUTME: Tests for Project and Workstream models.
// ABOUTME: Validates creation, identity, equality, serialization, and workstream management.

@testable import Dockyard
import XCTest

final class ProjectTests: XCTestCase {
    private static let testSuiteName = "dockyard.tests"
    private let testDefaults = UserDefaults(suiteName: testSuiteName)!

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: Self.testSuiteName)
        super.tearDown()
    }

    func testCreation() {
        let project = Project(name: "myapp", directory: "/Users/test/myapp")
        XCTAssertEqual(project.name, "myapp")
        XCTAssertEqual(project.directory, "/Users/test/myapp")
    }

    func testUniqueIDs() {
        let a = Project(name: "a", directory: "/a")
        let b = Project(name: "b", directory: "/b")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testExplicitID() {
        let id = UUID()
        let project = Project(name: "test", directory: "/test", id: id)
        XCTAssertEqual(project.id, id)
    }

    func testHashable() {
        let id = UUID()
        let a = Project(name: "test", directory: "/test", id: id)
        let b = Project(name: "test", directory: "/test", id: id)
        XCTAssertEqual(a, b)

        var set: Set<Project> = []
        set.insert(a)
        XCTAssertTrue(set.contains(b))
    }

    func testMutableProperties() {
        var project = Project(name: "old", directory: "/old")
        project.name = "new"
        project.directory = "/new"
        XCTAssertEqual(project.name, "new")
        XCTAssertEqual(project.directory, "/new")
    }

    func testProjectOverviewRejectsWorktreesLoadedForPreviousProject() {
        let staleWorktrees = [
            WorktreeInfo(
                path: "/Users/test/.dockyard/worktrees/dockyard/old-task",
                branch: "dy/old-task",
                isDirty: false,
                isMain: false,
                hasUnpushedCommits: false,
                hasBranchCommits: false
            ),
        ]

        XCTAssertNil(
            ProjectOverviewState.worktreesToApply(
                staleWorktrees,
                loadedFor: "/Users/test/repos/dockyard",
                currentDirectory: "/Users/test/repos/portfolio"
            )
        )
    }

    func testTriageSortPutsMainFirstThenDirtyThenAheadThenClean() {
        func wt(_ branch: String, dirty: Bool = false, main: Bool = false, ahead: Bool = false) -> WorktreeInfo {
            WorktreeInfo(
                path: "/wt/\(branch)",
                branch: branch,
                isDirty: dirty,
                isMain: main,
                hasUnpushedCommits: false,
                hasBranchCommits: ahead
            )
        }

        let sorted = ProjectOverviewState.triageSorted([
            wt("clean-b"),
            wt("ahead-a", ahead: true),
            wt("main", main: true),
            wt("dirty-a", dirty: true),
            wt("clean-a"),
            wt("dirty-b", dirty: true, ahead: true),
        ])

        XCTAssertEqual(
            sorted.map(\.branch),
            ["main", "dirty-a", "dirty-b", "ahead-a", "clean-a", "clean-b"]
        )
    }

    func testWorktreeReviewStatusClassifiesSafetyAndPullRequestState() {
        func wt(dirty: Bool = false, ahead: Bool = false) -> WorktreeInfo {
            WorktreeInfo(
                path: "/wt/feature",
                branch: "feature",
                isDirty: dirty,
                isMain: false,
                hasUnpushedCommits: false,
                hasBranchCommits: ahead
            )
        }

        XCTAssertEqual(
            ProjectOverviewState.reviewStatus(
                for: wt(dirty: true, ahead: true),
                pullRequestState: "MERGED",
                isPullRequestLookupComplete: true
            ),
            .dirty,
            "Uncommitted changes must remain the highest-priority safety signal"
        )
        XCTAssertEqual(
            ProjectOverviewState.reviewStatus(
                for: wt(),
                pullRequestState: nil,
                isPullRequestLookupComplete: false
            ),
            .clean,
            "Git can prove a branch clean without GitHub metadata"
        )
        XCTAssertEqual(
            ProjectOverviewState.reviewStatus(
                for: wt(ahead: true),
                pullRequestState: "MERGED",
                isPullRequestLookupComplete: true
            ),
            .mergedPullRequest
        )
        XCTAssertEqual(
            ProjectOverviewState.reviewStatus(
                for: wt(ahead: true),
                pullRequestState: "OPEN",
                isPullRequestLookupComplete: true
            ),
            .ahead
        )
        XCTAssertEqual(
            ProjectOverviewState.reviewStatus(
                for: wt(ahead: true),
                pullRequestState: nil,
                isPullRequestLookupComplete: false
            ),
            .unknown,
            "An unavailable PR lookup must not imply the branch is unmerged"
        )
    }

    func testCodableRoundTrip() throws {
        let projects = [
            Project(name: "alpha", directory: "/Users/test/alpha"),
            Project(name: "beta", directory: "/Users/test/beta"),
        ]
        let data = try JSONEncoder().encode(projects)
        let decoded = try JSONDecoder().decode([Project].self, from: data)
        XCTAssertEqual(projects, decoded)
    }

    func testCodablePreservesID() throws {
        let original = Project(name: "test", directory: "/test")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.directory, decoded.directory)
    }

    func testProjectStoreRoundTrip() {
        let projects = [
            Project(name: "one", directory: "/one"),
            Project(name: "two", directory: "/two"),
        ]
        ProjectStore.save(projects, defaults: testDefaults)
        let loaded = ProjectStore.load(defaults: testDefaults)
        XCTAssertEqual(projects, loaded)
    }

    func testProjectStoreSkipsMalformedRecordWithoutHidingHealthyProjects() throws {
        let first = Project(name: "first", directory: "/first")
        let second = Project(name: "second", directory: "/second")
        let encoded = try JSONEncoder().encode([first, second])
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        records.insert(
            [
                "id": UUID().uuidString,
                "name": "missing required project fields",
            ],
            at: 1
        )
        testDefaults.set(
            try JSONSerialization.data(withJSONObject: records),
            forKey: "dockyard.projects"
        )

        let loaded = ProjectStore.load(defaults: testDefaults)

        XCTAssertEqual(loaded.map(\.id), [first.id, second.id])
        XCTAssertEqual(loaded.map(\.name), ["first", "second"])
        XCTAssertEqual(loaded.map(\.directory), ["/first", "/second"])
    }

    func testProjectStoreRejectsInvalidTopLevelPayload() {
        testDefaults.set(Data(#"{"unexpected":"object"}"#.utf8), forKey: "dockyard.projects")

        XCTAssertTrue(ProjectStore.load(defaults: testDefaults).isEmpty)
    }

    func testProjectDefaultsToNoWorkstreams() {
        let project = Project(name: "test", directory: "/test")
        XCTAssertTrue(project.workstreams.isEmpty)
    }

    func testWorkstreamCreation() {
        let ws = Workstream(name: "feature-auth")
        XCTAssertEqual(ws.name, "feature-auth")
        XCTAssertEqual(ws.stage, .auto)
    }

    func testWorkstreamStageAutoFollowsPullRequestState() {
        XCTAssertEqual(WorkstreamStage.auto.displayStage(prState: "MERGED"), .done)
        XCTAssertEqual(WorkstreamStage.auto.displayStage(prState: "OPEN"), .review)
        XCTAssertEqual(WorkstreamStage.auto.displayStage(prState: nil), .normal)
        XCTAssertEqual(WorkstreamStage.auto.displayStage(prState: "CLOSED"), .normal)
    }

    func testWorkstreamStageManualOverridesPullRequestState() {
        XCTAssertEqual(WorkstreamStage.working.displayStage(prState: "MERGED"), .normal)
        XCTAssertEqual(WorkstreamStage.review.displayStage(prState: nil), .review)
        XCTAssertEqual(WorkstreamStage.done.displayStage(prState: "OPEN"), .done)
    }

    func testWorkstreamReportsManualStageOnlyForOverrides() {
        XCTAssertFalse(Workstream(name: "auto").isStageManuallySet)
        XCTAssertTrue(Workstream(name: "review", stage: .review).isStageManuallySet)
    }

    func testWorkstreamDecodingWithoutStageDefaultsToAuto() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "legacy",
          "worktreePath": "/tmp/legacy",
          "bypassPermissions": false,
          "lastAccessedAt": 0
        }
        """

        let decoded = try JSONDecoder().decode(Workstream.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.stage, .auto)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "legacy")
        XCTAssertEqual(decoded.worktreePath, "/tmp/legacy")
    }

    func testWorkstreamDecodingUnknownStageDefaultsToAuto() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "future",
          "worktreePath": null,
          "bypassPermissions": true,
          "lastAccessedAt": 0,
          "stage": "blocked"
        }
        """

        let decoded = try JSONDecoder().decode(Workstream.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.stage, .auto)
    }

    func testWorkstreamCodablePreservesExplicitStage() throws {
        let original = Workstream(name: "review-me", stage: .review)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Workstream.self, from: data)

        XCTAssertEqual(decoded.stage, .review)
        XCTAssertEqual(decoded, original)
    }

    func testProjectWithWorkstreams() {
        var project = Project(name: "app", directory: "/app")
        project.workstreams.append(Workstream(name: "backend"))
        project.workstreams.append(Workstream(name: "frontend"))
        XCTAssertEqual(project.workstreams.count, 2)
        XCTAssertNotEqual(project.workstreams[0].id, project.workstreams[1].id)
    }

    func testWorkstreamsCodableRoundTrip() throws {
        let project = Project(
            name: "app",
            directory: "/app",
            workstreams: [
                Workstream(name: "main"),
                Workstream(name: "bugfix"),
            ]
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(project, decoded)
        XCTAssertEqual(decoded.workstreams.count, 2)
        XCTAssertEqual(decoded.workstreams[0].name, "main")
        XCTAssertEqual(decoded.workstreams[1].name, "bugfix")
    }

    func testWorkstreamCodingCLIDecodesMissingValueAsNil() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "name": "legacy",
          "worktreePath": "/repo/.dockyard/worktrees/legacy",
          "bypassPermissions": false,
          "lastAccessedAt": "2026-06-17T18:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Workstream.self, from: Data(json.utf8))

        XCTAssertNil(decoded.codingCLI)
    }

    func testWorkstreamCodingCLIRoundTripsSetValue() throws {
        let original = Workstream(
            name: "use-codex",
            worktreePath: "/repo/.dockyard/worktrees/use-codex",
            codingCLI: "codex"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workstream.self, from: data)

        XCTAssertEqual(decoded.codingCLI, "codex")
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.worktreePath, original.worktreePath)
    }

    func testProjectStoreWithWorkstreams() {
        let projects = [
            Project(name: "one", directory: "/one", workstreams: [
                Workstream(name: "dev"),
            ]),
        ]
        ProjectStore.save(projects, defaults: testDefaults)
        let loaded = ProjectStore.load(defaults: testDefaults)
        XCTAssertEqual(loaded.first?.workstreams.count, 1)
        XCTAssertEqual(loaded.first?.workstreams.first?.name, "dev")
    }

    func testMoveProjectsPreservesWorkstreams() {
        let carriedWorkstream = Workstream(name: "carried")
        let first = Project(name: "first", directory: "/first", workstreams: [carriedWorkstream])
        let second = Project(name: "second", directory: "/second")
        let third = Project(name: "third", directory: "/third")
        var projects = [first, second, third]

        moveProjects(&projects, fromOffsets: IndexSet(integer: 0), toOffset: projects.count)

        XCTAssertEqual(projects.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(projects.last?.workstreams.map(\.id), [carriedWorkstream.id])
    }

    func testMoveWorkstreamsOnlyChangesTargetProject() {
        let targetFirst = Workstream(name: "target-first")
        let targetSecond = Workstream(name: "target-second")
        let other = Workstream(name: "other")
        let targetProject = Project(name: "target", directory: "/target", workstreams: [targetFirst, targetSecond])
        let otherProject = Project(name: "other", directory: "/other", workstreams: [other])
        var projects = [targetProject, otherProject]

        moveWorkstreams(
            in: &projects,
            projectID: targetProject.id,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 2
        )

        XCTAssertEqual(projects[0].workstreams.map(\.id), [targetSecond.id, targetFirst.id])
        XCTAssertEqual(projects[1].workstreams.map(\.id), [other.id])
    }

    func testSidebarManualOrderMigrationSeedsByRecencyOnce() {
        let oldWorkstream = Workstream(
            name: "old-workstream",
            id: UUID(),
            lastAccessedAt: Date(timeIntervalSince1970: 10)
        )
        let newWorkstream = Workstream(
            name: "new-workstream",
            id: UUID(),
            lastAccessedAt: Date(timeIntervalSince1970: 30)
        )
        let oldProject = Project(
            name: "old-project",
            directory: "/old-project",
            workstreams: [oldWorkstream, newWorkstream],
            lastAccessedAt: Date(timeIntervalSince1970: 10)
        )
        let newProject = Project(
            name: "new-project",
            directory: "/new-project",
            lastAccessedAt: Date(timeIntervalSince1970: 30)
        )

        ProjectStore.save([oldProject, newProject], defaults: testDefaults)

        let seeded = SidebarManualOrderMigration.seedIfNeeded(defaults: testDefaults)

        XCTAssertEqual(seeded.map(\.id), [newProject.id, oldProject.id])
        XCTAssertEqual(seeded[1].workstreams.map(\.id), [newWorkstream.id, oldWorkstream.id])
        XCTAssertTrue(testDefaults.bool(forKey: SidebarManualOrderMigration.seededKey))

        ProjectStore.save([oldProject, newProject], defaults: testDefaults)
        let secondRun = SidebarManualOrderMigration.seedIfNeeded(defaults: testDefaults)

        XCTAssertEqual(secondRun.map(\.id), [oldProject.id, newProject.id])
        XCTAssertEqual(secondRun[0].workstreams.map(\.id), [oldWorkstream.id, newWorkstream.id])
    }
}
