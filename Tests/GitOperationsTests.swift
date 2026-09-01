// ABOUTME: Tests for GitOperations worktree resolution.
// ABOUTME: Validates detection of worktree directories and resolution to main repository.

@testable import Dockyard
import XCTest

private enum GitPushProcessDoubleError: Error {
    case launchFailed
}

private final class GitPushProcessDouble: GitPushProcess, @unchecked Sendable {
    private(set) var runCallCount = 0
    var result: GitPushProcessResult
    var error: Error?

    init(output: Data = Data(), terminationStatus: Int32 = 0) {
        result = GitPushProcessResult(output: output, terminationStatus: terminationStatus)
    }

    func run() throws -> GitPushProcessResult {
        runCallCount += 1
        if let error {
            throw error
        }
        return result
    }
}

final class GitOperationsTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - mainRepositoryPath

    func testMainRepositoryPathReturnsNilForNonGitDirectory() throws {
        let plainDir = tempDir.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plainDir, withIntermediateDirectories: true)

        XCTAssertNil(GitOperations.mainRepositoryPath(for: plainDir.path))
    }

    func testMainRepositoryPathReturnsNilForMainRepo() throws {
        let repoDir = tempDir.appendingPathComponent("main-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init"], in: repoDir)

        XCTAssertNil(GitOperations.mainRepositoryPath(for: repoDir.path))
    }

    func testMainRepositoryPathResolvesWorktreeToMainRepo() throws {
        let repoDir = tempDir.appendingPathComponent("main-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let worktreeDir = tempDir.appendingPathComponent("worktree-branch")
        git(["worktree", "add", "-b", "test-branch", worktreeDir.path], in: repoDir)

        let result = GitOperations.mainRepositoryPath(for: worktreeDir.path)
        XCTAssertEqual(
            URL(fileURLWithPath: result ?? "").standardizedFileURL.path,
            repoDir.standardizedFileURL.path
        )
    }

    func testMainRepositoryPathReturnsNilForNestedDirectoryInWorktree() throws {
        let repoDir = tempDir.appendingPathComponent("main-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let worktreeDir = tempDir.appendingPathComponent("worktree-branch")
        git(["worktree", "add", "-b", "test-branch", worktreeDir.path], in: repoDir)

        // A subdirectory inside the worktree doesn't have its own .git file
        let subDir = worktreeDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        XCTAssertNil(GitOperations.mainRepositoryPath(for: subDir.path))
    }

    // MARK: - registeredWorktreePath and removeWorktree

    func testRegisteredWorktreePathAcceptsRegisteredNonMainWorktree() throws {
        let repoDir = makeRepository(named: "registered-main")
        let worktreeDir = tempDir.appendingPathComponent("registered-worktree")
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/registered", worktreeDir.path], in: repoDir))

        XCTAssertEqual(
            GitOperations.registeredWorktreePath(
                projectPath: repoDir.path,
                candidatePath: worktreeDir.path
            ),
            worktreeDir.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testRegisteredWorktreePathRejectsMainCheckoutAndUnrelatedDirectory() throws {
        let repoDir = makeRepository(named: "rejected-main")
        let nestedDir = repoDir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let unrelatedDir = tempDir.appendingPathComponent("unrelated-directory")
        try FileManager.default.createDirectory(at: unrelatedDir, withIntermediateDirectories: true)

        XCTAssertNil(
            GitOperations.registeredWorktreePath(
                projectPath: repoDir.path,
                candidatePath: repoDir.path
            )
        )
        XCTAssertNil(
            GitOperations.registeredWorktreePath(
                projectPath: nestedDir.path,
                candidatePath: repoDir.path
            ),
            "The actual main checkout must be rejected even when the project path is nested"
        )
        XCTAssertNil(
            GitOperations.registeredWorktreePath(
                projectPath: nestedDir.path,
                candidatePath: unrelatedDir.path
            )
        )
    }

    func testRemoveWorktreeRejectsUnregisteredDirectoryWithoutDeletingIt() throws {
        let repoDir = makeRepository(named: "remove-reject-main")
        let unrelatedDir = tempDir.appendingPathComponent("remove-reject-unrelated")
        try FileManager.default.createDirectory(at: unrelatedDir, withIntermediateDirectories: true)
        let sentinel = unrelatedDir.appendingPathComponent("keep.txt")
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)

        XCTAssertFalse(
            GitOperations.removeWorktree(
                projectPath: repoDir.path,
                worktreePath: unrelatedDir.path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testRemoveWorktreeRejectsMainCheckoutWithoutDeletingIt() throws {
        let repoDir = makeRepository(named: "remove-main")

        XCTAssertFalse(
            GitOperations.removeWorktree(
                projectPath: repoDir.path,
                worktreePath: repoDir.path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoDir.appendingPathComponent(".git").path))
        XCTAssertTrue(git(["rev-parse", "--verify", "refs/heads/main"], in: repoDir))
    }

    func testRemoveWorktreeRemovesRegisteredWorktreeButKeepsBranch() throws {
        let repoDir = makeRepository(named: "remove-success-main")
        let worktreeDir = tempDir.appendingPathComponent("remove-success-worktree")
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/remove-success", worktreeDir.path], in: repoDir))

        XCTAssertTrue(
            GitOperations.removeWorktree(
                projectPath: repoDir.path,
                worktreePath: worktreeDir.path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeDir.path))
        XCTAssertTrue(
            git(["rev-parse", "--verify", "refs/heads/feature/remove-success"], in: repoDir),
            "The caller owns branch deletion after a successful worktree removal"
        )
    }

    func testRemoveWorktreeFailureKeepsRegisteredDirectoryAndBranch() throws {
        let repoDir = makeRepository(named: "remove-failure-main")
        let worktreeDir = tempDir.appendingPathComponent("remove-failure-worktree")
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/remove-failure", worktreeDir.path], in: repoDir))
        XCTAssertTrue(git(["worktree", "lock", worktreeDir.path], in: repoDir))

        XCTAssertNil(
            GitOperations.registeredWorktreePath(
                projectPath: repoDir.path,
                candidatePath: worktreeDir.path
            ),
            "Locked worktrees must be rejected before teardown starts"
        )

        XCTAssertFalse(
            GitOperations.removeWorktree(
                projectPath: repoDir.path,
                worktreePath: worktreeDir.path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeDir.path))
        XCTAssertTrue(git(["rev-parse", "--verify", "refs/heads/feature/remove-failure"], in: repoDir))
    }

    // MARK: - defaultBranch

    func testDefaultBranchReturnsLocalMainWhenNoRemote() throws {
        let repoDir = tempDir.appendingPathComponent("no-remote")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let branch = GitOperations.defaultBranch(at: repoDir.path)
        XCTAssertEqual(branch, "main")
    }

    func testDefaultBranchReturnsMasterWhenNoMainBranch() throws {
        let repoDir = tempDir.appendingPathComponent("master-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "master"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let branch = GitOperations.defaultBranch(at: repoDir.path)
        XCTAssertEqual(branch, "master")
    }

    func testDefaultBranchReturnsHEADWhenNeitherMainNorMasterExist() throws {
        let repoDir = tempDir.appendingPathComponent("custom-branch")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "develop"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let branch = GitOperations.defaultBranch(at: repoDir.path)
        XCTAssertEqual(branch, "HEAD")
    }

    func testDefaultBranchPrefersOriginOverLocal() throws {
        // Create a non-bare "remote" repo with a commit on main
        let remoteDir = tempDir.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: remoteDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: remoteDir)

        // Clone it so we have origin/main
        let repoDir = tempDir.appendingPathComponent("cloned")
        git(["clone", remoteDir.path, repoDir.path], in: tempDir)

        let branch = GitOperations.defaultBranch(at: repoDir.path)
        XCTAssertTrue(branch.contains("origin"), "Expected origin-prefixed branch, got: \(branch)")
    }

    // MARK: - fetchDefaultBranch

    func testFetchDefaultBranchDoesNotCrashWithoutRemote() throws {
        let repoDir = tempDir.appendingPathComponent("no-remote-fetch")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        // Should return silently without crashing
        GitOperations.fetchDefaultBranch(at: repoDir.path)
    }

    func testFetchDefaultBranchDoesNotCrashForNonGitDirectory() throws {
        let plainDir = tempDir.appendingPathComponent("not-a-repo")
        try FileManager.default.createDirectory(at: plainDir, withIntermediateDirectories: true)

        // Should return silently without crashing
        GitOperations.fetchDefaultBranch(at: plainDir.path)
    }

    func testFetchDefaultBranchDoesNotCrashWithUnreachableRemote() throws {
        let repoDir = tempDir.appendingPathComponent("bad-remote")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)
        git(["remote", "add", "origin", "https://invalid.example.com/repo.git"], in: repoDir)

        // Should fail silently (timeout or network error)
        GitOperations.fetchDefaultBranch(at: repoDir.path)
    }

    // MARK: - currentBranch

    func testCurrentBranchReturnsActiveBranch() throws {
        let repoDir = tempDir.appendingPathComponent("branch-test")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        XCTAssertEqual(GitOperations.currentBranch(at: repoDir.path), "main")
    }

    func testCurrentBranchReturnsNilForNonGitDirectory() throws {
        let plainDir = tempDir.appendingPathComponent("not-a-repo")
        try FileManager.default.createDirectory(at: plainDir, withIntermediateDirectories: true)

        XCTAssertNil(GitOperations.currentBranch(at: plainDir.path))
    }

    func testCurrentBranchReturnsWorktreeBranch() throws {
        let repoDir = tempDir.appendingPathComponent("main-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let worktreeDir = tempDir.appendingPathComponent("wt")
        git(["worktree", "add", "-b", "dy/my-feature", worktreeDir.path], in: repoDir)

        XCTAssertEqual(GitOperations.currentBranch(at: worktreeDir.path), "dy/my-feature")
    }

    // MARK: - pushCurrentBranch

    func testPushCurrentBranchPreservesCommandAndReturnsCapturedOutput() {
        let process = GitPushProcessDouble(output: Data("pushed\n".utf8))

        let result = GitOperations.pushCurrentBranch(
            at: "/tmp/worktree",
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        ) { executableURL, arguments, maximumOutputBytes in
            XCTAssertEqual(executableURL.path, "/usr/bin/git")
            XCTAssertEqual(arguments, ["-C", "/tmp/worktree", "push", "-u", "origin", "HEAD"])
            XCTAssertEqual(maximumOutputBytes, GitOperations.maximumPushOutputBytes)
            return process
        }

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output, "pushed\n")
        XCTAssertEqual(process.runCallCount, 1)
    }

    func testPushCurrentBranchPreservesNonzeroExitStatus() {
        let process = GitPushProcessDouble(
            output: Data("remote rejected\n".utf8),
            terminationStatus: 1
        )

        let result = GitOperations.pushCurrentBranch(
            at: "/tmp/worktree",
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        ) { _, _, _ in process }

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.output, "remote rejected\n")
    }

    func testPushCurrentBranchReturnsFailureWhenProcessCannotLaunch() {
        let process = GitPushProcessDouble()
        process.error = GitPushProcessDoubleError.launchFailed

        let result = GitOperations.pushCurrentBranch(
            at: "/tmp/worktree",
            gitExecutableURL: URL(fileURLWithPath: "/usr/bin/git")
        ) { _, _, _ in process }

        XCTAssertFalse(result.success)
        XCTAssertFalse(result.output.isEmpty)
    }

    func testGitPushOutputCollectorCapsChunkedOutput() {
        let collector = GitPushOutputCollector(maximumOutputBytes: 64 * 1024)

        collector.ingest(Data(repeating: 0x41, count: 40 * 1024))
        collector.ingest(Data(repeating: 0x42, count: 40 * 1024))
        collector.ingest(Data(repeating: 0x43, count: 8 * 1024))

        let output = collector.snapshot
        XCTAssertEqual(output.count, 64 * 1024)
        XCTAssertEqual(output.prefix(40 * 1024), Data(repeating: 0x41, count: 40 * 1024))
        XCTAssertEqual(output.suffix(24 * 1024), Data(repeating: 0x42, count: 24 * 1024))
    }

    func testFoundationGitPushProcessDrainsBeforeReturningAndCapsOutput() throws {
        let process = FoundationGitPushProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "/usr/bin/yes x | /usr/bin/head -c 131072; exit 7"],
            maximumOutputBytes: 64 * 1024
        )

        let result = try process.run()

        XCTAssertEqual(result.terminationStatus, 7)
        XCTAssertEqual(result.output.count, 64 * 1024)
        XCTAssertTrue(result.output.allSatisfy { $0 == 0x78 || $0 == 0x0A })
    }

    // MARK: - deleteLocalBranch

    func testDeleteLocalBranchRemovesBranch() throws {
        let repoDir = tempDir.appendingPathComponent("delete-branch")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)
        git(["branch", "feature"], in: repoDir)

        GitOperations.deleteLocalBranch(at: repoDir.path, branchName: "feature")

        // Verify branch no longer exists
        let result = git(["rev-parse", "--verify", "refs/heads/feature"], in: repoDir)
        XCTAssertFalse(result, "Branch should have been deleted")
    }

    // MARK: - fetchDefaultBranch

    func testFetchDefaultBranchSkipsWithoutRemote() throws {
        let repoDir = tempDir.appendingPathComponent("no-remote-update")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        // Should return silently without crashing
        GitOperations.fetchDefaultBranch(at: repoDir.path)
    }

    func testFetchDefaultBranchDoesNotMoveLocalRef() throws {
        // Create a "remote" repo
        let remoteDir = tempDir.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: remoteDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: remoteDir)

        // Clone it
        let repoDir = tempDir.appendingPathComponent("local")
        git(["clone", remoteDir.path, repoDir.path], in: tempDir)

        // Record the initial commit
        let beforeSHA = gitOutput(["rev-parse", "refs/heads/main"], in: repoDir)

        // Add a new commit to remote
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "second"], in: remoteDir)

        // Fetch should update remote tracking ref but not local main
        GitOperations.fetchDefaultBranch(at: repoDir.path)

        let afterSHA = gitOutput(["rev-parse", "refs/heads/main"], in: repoDir)
        XCTAssertEqual(beforeSHA, afterSHA, "Local main should not have moved")

        let remoteSHA = gitOutput(["rev-parse", "refs/remotes/origin/main"], in: repoDir)
        XCTAssertNotEqual(beforeSHA, remoteSHA, "Remote tracking ref should have advanced")
    }

    // MARK: - updateDefaultBranch

    func testUpdateDefaultBranchFastForwardsCleanCheckout() throws {
        let (remoteDir, repoDir) = try makeRemoteClone(named: "clean-default-update")
        let remoteSHA = try advanceRemote(remoteDir)

        GitOperations.updateDefaultBranch(at: repoDir.path)

        XCTAssertEqual(gitOutput(["rev-parse", "refs/heads/main"], in: repoDir), remoteSHA)
        XCTAssertEqual(gitOutput(["rev-parse", "refs/remotes/origin/main"], in: repoDir), remoteSHA)
        XCTAssertEqual(
            try String(contentsOf: repoDir.appendingPathComponent("remote.txt"), encoding: .utf8),
            "remote change"
        )
        XCTAssertEqual(gitOutput(["status", "--porcelain"], in: repoDir), "")
    }

    func testUpdateDefaultBranchPreservesStagedCheckout() throws {
        try assertDirtyDefaultCheckoutIsPreserved(.staged)
    }

    func testUpdateDefaultBranchPreservesUnstagedCheckout() throws {
        try assertDirtyDefaultCheckoutIsPreserved(.unstaged)
    }

    func testUpdateDefaultBranchPreservesUntrackedCheckout() throws {
        try assertDirtyDefaultCheckoutIsPreserved(.untracked)
    }

    // MARK: - fileStatuses

    func testFileStatusesReturnsModifiedForTrackedChanges() throws {
        let repoDir = tempDir.appendingPathComponent("status-modified")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)

        let filePath = repoDir.appendingPathComponent("tracked.txt")
        try "original".write(to: filePath, atomically: true, encoding: .utf8)
        git(["add", "tracked.txt"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "-m", "init"], in: repoDir)

        try "changed".write(to: filePath, atomically: true, encoding: .utf8)

        let statuses = GitOperations.fileStatuses(at: repoDir.path)
        XCTAssertEqual(statuses["tracked.txt"], .modified)
    }

    func testFileStatusesReturnsUntrackedForNewFiles() throws {
        let repoDir = tempDir.appendingPathComponent("status-untracked")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        try "new file".write(
            to: repoDir.appendingPathComponent("untracked.txt"),
            atomically: true, encoding: .utf8
        )

        let statuses = GitOperations.fileStatuses(at: repoDir.path)
        XCTAssertEqual(statuses["untracked.txt"], .untracked)
    }

    func testFileStatusesReturnsIgnoredForGitignored() throws {
        let repoDir = tempDir.appendingPathComponent("status-ignored")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)

        try "build/\n".write(
            to: repoDir.appendingPathComponent(".gitignore"),
            atomically: true, encoding: .utf8
        )
        let buildDir = repoDir.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try "artifact".write(
            to: buildDir.appendingPathComponent("output.o"),
            atomically: true, encoding: .utf8
        )

        let statuses = GitOperations.fileStatuses(at: repoDir.path)
        XCTAssertEqual(statuses["build"], .ignored)
    }

    func testFileStatusesReturnsEmptyForNonGitDirectory() throws {
        let plainDir = tempDir.appendingPathComponent("no-git")
        try FileManager.default.createDirectory(at: plainDir, withIntermediateDirectories: true)

        let statuses = GitOperations.fileStatuses(at: plainDir.path)
        XCTAssertTrue(statuses.isEmpty)
    }

    func testFileStatusesHandlesRenames() throws {
        let repoDir = tempDir.appendingPathComponent("status-rename")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)

        try "content".write(
            to: repoDir.appendingPathComponent("old.txt"),
            atomically: true, encoding: .utf8
        )
        git(["add", "old.txt"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "-m", "init"], in: repoDir)

        git(["mv", "old.txt", "new.txt"], in: repoDir)

        let statuses = GitOperations.fileStatuses(at: repoDir.path)
        XCTAssertEqual(statuses["new.txt"], .modified)
    }

    // MARK: - pruneCleanWorktrees

    func testPruneCleanWorktreesPrunesOnlyRequestedPaths() throws {
        let repoDir = tempDir.appendingPathComponent("prune-filtered")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let worktreeA = tempDir.appendingPathComponent("worktree-a")
        let worktreeB = tempDir.appendingPathComponent("worktree-b")
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/a", worktreeA.path], in: repoDir))
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/b", worktreeB.path], in: repoDir))

        let pruned = GitOperations.pruneCleanWorktrees(
            at: repoDir.path,
            onlyPaths: Set([worktreeA.path])
        )

        XCTAssertEqual(pruned, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeB.path))
    }

    func testPruneCleanWorktreesDeletesLocalBranch() throws {
        let repoDir = tempDir.appendingPathComponent("prune-branch")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let worktreeA = tempDir.appendingPathComponent("worktree-a")
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/a", worktreeA.path], in: repoDir))

        let pruned = GitOperations.pruneCleanWorktrees(at: repoDir.path)

        XCTAssertEqual(pruned, 1)
        XCTAssertFalse(
            git(["rev-parse", "--verify", "refs/heads/feature/a"], in: repoDir),
            "Branch of pruned worktree should have been deleted"
        )
        XCTAssertTrue(
            git(["rev-parse", "--verify", "refs/heads/main"], in: repoDir),
            "Default branch must survive pruning"
        )
    }

    func testPruneCleanWorktreesRemovesWorktreeWithPopulatedSubmodule() throws {
        // A clean worktree with an initialized submodule makes plain
        // `git worktree remove` fail with "working trees containing submodules
        // cannot be moved or removed", so pruning must force-remove.
        let subDir = tempDir.appendingPathComponent("submodule-repo")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: subDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: subDir)

        let repoDir = tempDir.appendingPathComponent("prune-submodule")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "protocol.file.allow=always", "submodule", "add", subDir.path, "sub"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "-m", "add submodule"], in: repoDir)

        let worktree = tempDir.appendingPathComponent("worktree-sub")
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/sub", worktree.path], in: repoDir))
        XCTAssertTrue(git(["-c", "protocol.file.allow=always", "submodule", "update", "--init"], in: worktree))

        let pruned = GitOperations.pruneCleanWorktrees(at: repoDir.path)

        XCTAssertEqual(pruned, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
    }

    // MARK: - listWorktreesWithInfo

    func testListWorktreesWithInfoReportsStatusPerWorktree() throws {
        let repoDir = tempDir.appendingPathComponent("list-info")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "init"], in: repoDir)

        let cleanWT = tempDir.appendingPathComponent("wt-clean")
        let dirtyWT = tempDir.appendingPathComponent("wt-dirty")
        let aheadWT = tempDir.appendingPathComponent("wt-ahead")
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/clean", cleanWT.path], in: repoDir))
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/dirty", dirtyWT.path], in: repoDir))
        XCTAssertTrue(git(["worktree", "add", "-b", "feature/ahead", aheadWT.path], in: repoDir))

        try "wip".write(to: dirtyWT.appendingPathComponent("wip.txt"), atomically: true, encoding: .utf8)
        git(["-c", "user.email=test@test.com", "-c", "user.name=Test",
             "commit", "--allow-empty", "-m", "work"], in: aheadWT)

        let infos = GitOperations.listWorktreesWithInfo(at: repoDir.path)
        XCTAssertEqual(infos.count, 4)

        let byBranch = Dictionary(uniqueKeysWithValues: infos.compactMap { info in
            info.branch.map { ($0, info) }
        })
        XCTAssertEqual(byBranch["main"]?.isMain, true)
        XCTAssertEqual(byBranch["feature/clean"]?.isDirty, false)
        XCTAssertEqual(byBranch["feature/clean"]?.hasBranchCommits, false)
        XCTAssertEqual(byBranch["feature/dirty"]?.isDirty, true)
        XCTAssertEqual(byBranch["feature/ahead"]?.isDirty, false)
        XCTAssertEqual(byBranch["feature/ahead"]?.hasBranchCommits, true)
    }

    // MARK: - updateDefaultBranch Helpers

    private enum DirtyCheckoutKind: String {
        case staged
        case unstaged
        case untracked
    }

    private func makeRemoteClone(named name: String) throws -> (remote: URL, clone: URL) {
        let remoteDir = tempDir.appendingPathComponent("\(name)-remote")
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        XCTAssertTrue(git(["init", "-b", "main"], in: remoteDir))
        try "base".write(
            to: remoteDir.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(git(["add", "tracked.txt"], in: remoteDir))
        XCTAssertTrue(git([
            "-c", "user.email=test@test.com", "-c", "user.name=Test",
            "commit", "-m", "initial",
        ], in: remoteDir))

        let repoDir = tempDir.appendingPathComponent("\(name)-local")
        XCTAssertTrue(git(["clone", remoteDir.path, repoDir.path], in: tempDir))
        return (remoteDir, repoDir)
    }

    private func advanceRemote(_ remoteDir: URL) throws -> String {
        try "remote change".write(
            to: remoteDir.appendingPathComponent("remote.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(git(["add", "remote.txt"], in: remoteDir))
        XCTAssertTrue(git([
            "-c", "user.email=test@test.com", "-c", "user.name=Test",
            "commit", "-m", "remote change",
        ], in: remoteDir))
        return gitOutput(["rev-parse", "HEAD"], in: remoteDir)
    }

    private func assertDirtyDefaultCheckoutIsPreserved(_ kind: DirtyCheckoutKind) throws {
        let (remoteDir, repoDir) = try makeRemoteClone(named: "dirty-\(kind.rawValue)")
        let trackedFile = repoDir.appendingPathComponent("tracked.txt")
        let untrackedFile = repoDir.appendingPathComponent("untracked.txt")

        switch kind {
        case .staged:
            try "staged change".write(to: trackedFile, atomically: true, encoding: .utf8)
            XCTAssertTrue(git(["add", "tracked.txt"], in: repoDir))
        case .unstaged:
            try "unstaged change".write(to: trackedFile, atomically: true, encoding: .utf8)
        case .untracked:
            try "untracked change".write(to: untrackedFile, atomically: true, encoding: .utf8)
        }

        let localSHABefore = gitOutput(["rev-parse", "refs/heads/main"], in: repoDir)
        let indexBefore = gitOutput(["ls-files", "--stage"], in: repoDir)
        let statusBefore = gitOutput(["status", "--porcelain"], in: repoDir)
        let trackedContentsBefore = try String(contentsOf: trackedFile, encoding: .utf8)
        let untrackedContentsBefore = try? String(contentsOf: untrackedFile, encoding: .utf8)
        let remoteSHA = try advanceRemote(remoteDir)

        GitOperations.updateDefaultBranch(at: repoDir.path)

        XCTAssertEqual(gitOutput(["rev-parse", "refs/heads/main"], in: repoDir), localSHABefore)
        XCTAssertEqual(gitOutput(["rev-parse", "refs/remotes/origin/main"], in: repoDir), remoteSHA)
        XCTAssertEqual(gitOutput(["ls-files", "--stage"], in: repoDir), indexBefore)
        XCTAssertEqual(gitOutput(["status", "--porcelain"], in: repoDir), statusBefore)
        XCTAssertEqual(try String(contentsOf: trackedFile, encoding: .utf8), trackedContentsBefore)
        XCTAssertEqual(try? String(contentsOf: untrackedFile, encoding: .utf8), untrackedContentsBefore)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: repoDir.appendingPathComponent("remote.txt").path)
        )
    }

    // MARK: - Helpers

    private func makeRepository(named name: String) -> URL {
        let repoDir = tempDir.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        XCTAssertTrue(git(["init", "-b", "main"], in: repoDir))
        XCTAssertTrue(git([
            "-c", "user.email=test@test.com", "-c", "user.name=Test",
            "commit", "--allow-empty", "-m", "init",
        ], in: repoDir))
        return repoDir
    }

    @discardableResult
    private func git(_ args: [String], in dir: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func gitOutput(_ args: [String], in dir: URL) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = dir
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
