// ABOUTME: Tests WorktreeHeadWatcher's HEAD-directory resolution for normal repos and
// ABOUTME: linked worktrees (where .git is a file pointing at the per-worktree git dir).

@testable import Dockyard
import XCTest

final class WorktreeHeadWatcherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dy-head-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testReturnsNilForNonGitDirectory() {
        XCTAssertNil(WorktreeHeadWatcher.headDirectory(forWorktree: root.path))
    }

    func testReturnsGitDirectoryForNormalRepo() throws {
        let gitDir = root.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let resolved = WorktreeHeadWatcher.headDirectory(forWorktree: root.path)
        XCTAssertEqual(resolved, gitDir.path)
    }

    func testResolvesGitdirPointerForLinkedWorktree() throws {
        // A linked worktree's .git is a file: "gitdir: <abs path to per-worktree dir>".
        let perWorktreeGitDir = root.appendingPathComponent("main/.git/worktrees/feature", isDirectory: true)
        try FileManager.default.createDirectory(at: perWorktreeGitDir, withIntermediateDirectories: true)

        let worktree = root.appendingPathComponent("feature", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        let gitFile = worktree.appendingPathComponent(".git")
        try "gitdir: \(perWorktreeGitDir.path)\n".write(to: gitFile, atomically: true, encoding: .utf8)

        let resolved = WorktreeHeadWatcher.headDirectory(forWorktree: worktree.path)
        XCTAssertEqual(resolved, perWorktreeGitDir.path)
    }

    func testReturnsNilWhenGitFileHasNoGitdirLine() throws {
        let worktree = root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        let gitFile = worktree.appendingPathComponent(".git")
        try "not a gitdir pointer\n".write(to: gitFile, atomically: true, encoding: .utf8)

        XCTAssertNil(WorktreeHeadWatcher.headDirectory(forWorktree: worktree.path))
    }
}
