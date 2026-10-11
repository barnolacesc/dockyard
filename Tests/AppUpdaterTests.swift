// ABOUTME: Verifies update-check subprocess output is drained and retained within a fixed bound.
// ABOUTME: Preserves the git count command while failing closed on malformed process results.

@testable import Dockyard
import Foundation
import XCTest

private enum UpdateCheckTestError: Error {
    case launch
}

private final class UpdateCheckProcessDouble: UpdateCheckProcess, @unchecked Sendable {
    var result: UpdateCheckProcessResult
    var runError: Error?
    private(set) var runCallCount = 0
    private(set) var waitCallCount = 0

    init(
        output: Data = Data(),
        terminationStatus: Int32 = 0,
        outputExceededLimit: Bool = false,
        didFinishOutput: Bool = true
    ) {
        result = UpdateCheckProcessResult(
            output: output,
            terminationStatus: terminationStatus,
            outputExceededLimit: outputExceededLimit,
            didFinishOutput: didFinishOutput
        )
    }

    func run() throws {
        runCallCount += 1
        if let runError { throw runError }
    }

    func waitForExit() -> UpdateCheckProcessResult {
        waitCallCount += 1
        return result
    }
}

final class AppUpdaterTests: XCTestCase {
    func testSourceUpdateBuildsWithoutTerminatingRunningApp() {
        XCTAssertEqual(SourceUpdateBuildMode.resolve(configuration: "Debug"), "build")
        XCTAssertEqual(SourceUpdateBuildMode.resolve(configuration: "Release"), "install-bg")
    }

    func testLatestNewReleaseTagParsesFirstTag() {
        let process = UpdateCheckProcessDouble(output: Data("v0.2.7\nv0.2.6\n".utf8))

        let tag = UpdateCheckCommandRunner.latestNewReleaseTag(at: "/tmp/dockyard source", from: "123b4d0") {
            executableURL,
            arguments,
            workingDirectoryURL,
            maximumOutputBytes in
            XCTAssertEqual(executableURL.path, "/usr/bin/git")
            XCTAssertEqual(arguments, ["tag", "--merged", "origin/main", "--no-merged", "123b4d0", "--sort=-v:refname"])
            XCTAssertEqual(workingDirectoryURL.path, "/tmp/dockyard source")
            XCTAssertEqual(maximumOutputBytes, 64 * 1024)
            return process
        }

        XCTAssertEqual(tag, "v0.2.7")
        XCTAssertEqual(process.runCallCount, 1)
        XCTAssertEqual(process.waitCallCount, 1)
    }

    func testLatestNewReleaseTagFiltersOutNonReleaseAndPrereleaseTags() {
        let process = UpdateCheckProcessDouble(
            output: Data("custom-tag\nv0.2.8-beta.1\nv0.2.8-rc1\nv0.2.7\nv0.2.6\n".utf8)
        )

        let tag = UpdateCheckCommandRunner.latestNewReleaseTag(at: "/tmp/dockyard source", from: "123b4d0") { _, _, _, _ in
            process
        }

        XCTAssertEqual(tag, "v0.2.7")
    }

    func testLatestNewReleaseTagReturnsNilWhenEmpty() {
        let process = UpdateCheckProcessDouble(output: Data("".utf8))

        let tag = UpdateCheckCommandRunner.latestNewReleaseTag(at: "/tmp", from: "123b4d0") { _, _, _, _ in
            process
        }

        XCTAssertNil(tag)
    }

    func testLatestNewReleaseTagFallsBackToHeadForInvalidCommit() {
        let process = UpdateCheckProcessDouble(output: Data("v0.2.7\n".utf8))

        let tag = UpdateCheckCommandRunner.latestNewReleaseTag(at: "/tmp", from: "invalid_hash") { _, arguments, _, _ in
            XCTAssertEqual(arguments, ["tag", "--merged", "origin/main", "--no-merged", "HEAD", "--sort=-v:refname"])
            return process
        }

        XCTAssertEqual(tag, "v0.2.7")
    }

    @MainActor
    func testUpdateChannelDefaultsAndMigration() throws {
        let suiteName = "test.dockyard.updateChannel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Default when nothing set
        XCTAssertEqual(AppUpdater.loadChannel(from: defaults), .releases)

        // Legacy bleedingEdge toggle migration
        defaults.set(true, forKey: "dockyard.bleedingEdge")
        XCTAssertEqual(AppUpdater.loadChannel(from: defaults), .mainCommits)

        // Explicit updateChannel overrides bleedingEdge
        defaults.set(UpdateChannel.releases.rawValue, forKey: AppUpdater.channelStorageKey)
        XCTAssertEqual(AppUpdater.loadChannel(from: defaults), .releases)

        defaults.set(UpdateChannel.mainCommits.rawValue, forKey: AppUpdater.channelStorageKey)
        XCTAssertEqual(AppUpdater.loadChannel(from: defaults), .mainCommits)
    }

    func testSuccessfulCountPreservesGitCommandAndWorkingDirectory() {
        let process = UpdateCheckProcessDouble(output: Data("  42\n".utf8))

        let count = UpdateCheckCommandRunner.commitsAhead(at: "/tmp/dockyard source", from: "123b4d0") {
            executableURL,
            arguments,
            workingDirectoryURL,
            maximumOutputBytes in
            XCTAssertEqual(executableURL.path, "/usr/bin/git")
            XCTAssertEqual(arguments, ["rev-list", "--count", "123b4d0..origin/main"])
            XCTAssertEqual(workingDirectoryURL.path, "/tmp/dockyard source")
            XCTAssertEqual(maximumOutputBytes, 64 * 1024)
            return process
        }

        XCTAssertEqual(count, 42)
        XCTAssertEqual(process.runCallCount, 1)
        XCTAssertEqual(process.waitCallCount, 1)
    }

    func testInvalidEmbeddedCommitFallsBackToHead() {
        let process = UpdateCheckProcessDouble(output: Data("0\n".utf8))

        let count = UpdateCheckCommandRunner.commitsAhead(at: "/tmp", from: "unknown") { _, arguments, _, _ in
            XCTAssertEqual(arguments, ["rev-list", "--count", "HEAD..origin/main"])
            return process
        }

        XCTAssertEqual(count, 0)
    }

    func testCollectorRetainsExactlyTheCapAcrossChunks() {
        let collector = UpdateCheckOutputCollector(maximumOutputBytes: 5)

        collector.ingest(Data("ab".utf8))
        collector.ingest(Data("cde".utf8))

        let snapshot = collector.snapshot
        XCTAssertEqual(snapshot.output, Data("abcde".utf8))
        XCTAssertFalse(snapshot.outputExceededLimit)
    }

    func testCollectorContinuesAcceptingChunksAfterOverflowWithoutGrowing() {
        let collector = UpdateCheckOutputCollector(maximumOutputBytes: 5)

        collector.ingest(Data("abc".utf8))
        collector.ingest(Data("def".utf8))
        collector.ingest(Data("ghi".utf8))

        let snapshot = collector.snapshot
        XCTAssertEqual(snapshot.output, Data("abcde".utf8))
        XCTAssertTrue(snapshot.outputExceededLimit)
    }

    func testFailsClosedOnOverflowIncompleteDrainAndNonzeroExit() {
        let overflow = UpdateCheckProcessDouble(
            output: Data("1".utf8),
            outputExceededLimit: true
        )
        XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp", from: "123b4d0") { _, _, _, _ in overflow })

        let incomplete = UpdateCheckProcessDouble(
            output: Data("1".utf8),
            didFinishOutput: false
        )
        XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp", from: "123b4d0") { _, _, _, _ in incomplete })

        let failed = UpdateCheckProcessDouble(
            output: Data("1".utf8),
            terminationStatus: 1
        )
        XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp", from: "123b4d0") { _, _, _, _ in failed })
    }

    func testFailsClosedOnMalformedInvalidAndNegativeOutput() {
        for output in [Data("many".utf8), Data([0xFF]), Data("-1".utf8)] {
            let process = UpdateCheckProcessDouble(output: output)
            XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp", from: "123b4d0") { _, _, _, _ in process })
        }
    }

    func testFailsClosedOnFactoryAndLaunchFailureWithoutWaiting() {
        XCTAssertNil(
            UpdateCheckCommandRunner.commitsAhead(at: "/tmp", from: "123b4d0") { _, _, _, _ in
                throw UpdateCheckTestError.launch
            }
        )

        let process = UpdateCheckProcessDouble()
        process.runError = UpdateCheckTestError.launch
        XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp", from: "123b4d0") { _, _, _, _ in process })
        XCTAssertEqual(process.runCallCount, 1)
        XCTAssertEqual(process.waitCallCount, 0)
    }

    func testFoundationProcessDrainsNoisyOutputBeforeReturning() throws {
        let process = FoundationUpdateCheckProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "/usr/bin/yes 7 | /usr/bin/head -c 131072"],
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            maximumOutputBytes: 64 * 1024
        )

        try process.run()
        let result = process.waitForExit()

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertTrue(result.didFinishOutput)
        XCTAssertTrue(result.outputExceededLimit)
        XCTAssertEqual(result.output.count, 64 * 1024)
    }
}
