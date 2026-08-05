// ABOUTME: Tests WorktreeHeadWatcher's HEAD-directory resolution and event recovery.
// ABOUTME: Covers linked worktrees plus replacement and removal of watched git directories.

@testable import Dockyard
import XCTest

final class WorktreeHeadWatcherTests: XCTestCase {
    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []

        func record(_ path: String) {
            lock.lock()
            paths.append(path)
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return paths.count
        }

        var lastPath: String? {
            lock.lock()
            defer { lock.unlock() }
            return paths.last
        }
    }

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

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func writeHead(in gitDirectory: URL, value: String) throws {
        try value.write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func triggerHeadChange(
        in gitDirectory: URL,
        recorder: EventRecorder,
        after baseline: Int
    ) throws -> Bool {
        let deadline = Date().addingTimeInterval(2)
        var attempt = 0
        while Date() < deadline {
            attempt += 1
            try writeHead(in: gitDirectory, value: "ref: refs/heads/test-\(attempt)\n")
            if waitUntil(timeout: 0.1, condition: { recorder.count > baseline }) {
                return true
            }
        }
        return recorder.count > baseline
    }

    private func makeNormalRepository() throws -> URL {
        let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try writeHead(in: gitDirectory, value: "ref: refs/heads/main\n")
        return gitDirectory
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

    func testReattachesAfterHeadDirectoryReplacement() throws {
        let originalGitDirectory = try makeNormalRepository()
        let recorder = EventRecorder()
        let watcher = WorktreeHeadWatcher(
            debounce: .milliseconds(20),
            reattachDelay: .milliseconds(20)
        ) { recorder.record($0) }
        watcher.sync(paths: [root.path])

        XCTAssertTrue(try triggerHeadChange(in: originalGitDirectory, recorder: recorder, after: 0))
        let initialBaseline = recorder.count

        let replacedGitDirectory = root.appendingPathComponent(".git.replaced", isDirectory: true)
        try FileManager.default.moveItem(at: originalGitDirectory, to: replacedGitDirectory)
        try FileManager.default.createDirectory(at: originalGitDirectory, withIntermediateDirectories: true)
        try writeHead(in: originalGitDirectory, value: "ref: refs/heads/replaced\n")

        XCTAssertTrue(waitUntil { recorder.count > initialBaseline })
        let replacementBaseline = recorder.count
        XCTAssertTrue(try triggerHeadChange(
            in: originalGitDirectory,
            recorder: recorder,
            after: replacementBaseline
        ))
        XCTAssertEqual(recorder.lastPath, root.path)
    }

    func testSyncRemovalCancelsPendingReattachment() throws {
        let originalGitDirectory = try makeNormalRepository()
        let recorder = EventRecorder()
        let watcher = WorktreeHeadWatcher(
            debounce: .milliseconds(20),
            reattachDelay: .milliseconds(200)
        ) { recorder.record($0) }
        watcher.sync(paths: [root.path])
        XCTAssertTrue(try triggerHeadChange(in: originalGitDirectory, recorder: recorder, after: 0))
        let initialBaseline = recorder.count

        let replacedGitDirectory = root.appendingPathComponent(".git.replaced", isDirectory: true)
        try FileManager.default.moveItem(at: originalGitDirectory, to: replacedGitDirectory)
        XCTAssertTrue(waitUntil { recorder.count > initialBaseline })
        watcher.sync(paths: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        try FileManager.default.createDirectory(at: originalGitDirectory, withIntermediateDirectories: true)
        let baseline = recorder.count
        for attempt in 1 ... 5 {
            try writeHead(in: originalGitDirectory, value: "ref: refs/heads/removed-\(attempt)\n")
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
        XCTAssertEqual(recorder.count, baseline)
    }

    func testStopCancelsPendingReattachment() throws {
        let originalGitDirectory = try makeNormalRepository()
        let recorder = EventRecorder()
        let watcher = WorktreeHeadWatcher(
            debounce: .milliseconds(20),
            reattachDelay: .milliseconds(200)
        ) { recorder.record($0) }
        watcher.sync(paths: [root.path])
        XCTAssertTrue(try triggerHeadChange(in: originalGitDirectory, recorder: recorder, after: 0))
        let initialBaseline = recorder.count

        let replacedGitDirectory = root.appendingPathComponent(".git.replaced", isDirectory: true)
        try FileManager.default.moveItem(at: originalGitDirectory, to: replacedGitDirectory)
        XCTAssertTrue(waitUntil { recorder.count > initialBaseline })
        watcher.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        try FileManager.default.createDirectory(at: originalGitDirectory, withIntermediateDirectories: true)
        let baseline = recorder.count
        for attempt in 1 ... 5 {
            try writeHead(in: originalGitDirectory, value: "ref: refs/heads/stopped-\(attempt)\n")
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
        XCTAssertEqual(recorder.count, baseline)
    }
}
