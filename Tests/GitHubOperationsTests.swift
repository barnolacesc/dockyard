// ABOUTME: Verifies read-only GitHub integration probes have deterministic process boundaries.
// ABOUTME: Keeps stalled or noisy git and gh commands from blocking repository refreshes.

@testable import Dockyard
import Foundation
import XCTest

private enum GitHubReadProbeTestError: Error {
    case launch
}

private final class GitHubReadProcessDouble: GitHubReadProcess, @unchecked Sendable {
    var result: GitHubReadProcessResult
    var waitResults: [Bool]
    var runError: Error?
    private(set) var runCallCount = 0
    private(set) var waitTimeouts: [TimeInterval] = []
    private(set) var terminateCallCount = 0
    private(set) var forceTerminateCallCount = 0

    init(
        output: Data = Data(),
        terminationStatus: Int32 = 0,
        outputExceededLimit: Bool = false,
        didFinishOutput: Bool = true,
        waitResults: [Bool] = [true]
    ) {
        result = GitHubReadProcessResult(
            output: output,
            terminationStatus: terminationStatus,
            outputExceededLimit: outputExceededLimit,
            didFinishOutput: didFinishOutput
        )
        self.waitResults = waitResults
    }

    func run() throws {
        runCallCount += 1
        if let runError { throw runError }
    }

    func waitForExit(timeout: TimeInterval) -> Bool {
        waitTimeouts.append(timeout)
        return waitResults.isEmpty ? false : waitResults.removeFirst()
    }

    func terminate() {
        terminateCallCount += 1
    }

    func forceTerminate() {
        forceTerminateCallCount += 1
    }
}

final class GitHubOperationsTests: XCTestCase {
    func testSuccessfulProbePreservesCommandAndTrimsOutput() {
        let process = GitHubReadProcessDouble(output: Data("  value\n".utf8))

        let output = GitHubOperations.runCommand(
            "/usr/local/bin/gh",
            args: ["pr", "list"],
            in: "/tmp/repo"
        ) { executableURL, arguments, workingDirectoryURL, maximumOutputBytes in
            XCTAssertEqual(executableURL.path, "/usr/local/bin/gh")
            XCTAssertEqual(arguments, ["pr", "list"])
            XCTAssertEqual(workingDirectoryURL.path, "/tmp/repo")
            XCTAssertEqual(maximumOutputBytes, GitHubOperations.maximumProbeOutputBytes)
            return process
        }

        XCTAssertEqual(output, "value")
        XCTAssertEqual(process.runCallCount, 1)
        XCTAssertEqual(process.waitTimeouts, [GitHubOperations.probeTimeout])
        XCTAssertEqual(process.terminateCallCount, 0)
        XCTAssertEqual(process.forceTerminateCallCount, 0)
    }

    func testCollectorRetainsOnlyCapAcrossChunks() {
        let collector = GitHubReadOutputCollector(maximumOutputBytes: 5)

        XCTAssertFalse(collector.ingest(Data("abc".utf8)))
        XCTAssertTrue(collector.ingest(Data("def".utf8)))
        XCTAssertTrue(collector.ingest(Data("ghi".utf8)))

        let snapshot = collector.snapshot
        XCTAssertEqual(snapshot.output, Data("abcde".utf8))
        XCTAssertTrue(snapshot.outputExceededLimit)
    }

    func testTimedOutProbeTerminatesThenForceTerminates() {
        let process = GitHubReadProcessDouble(waitResults: [false, false, true])

        let output = GitHubOperations.runCommand("/tmp/hung-gh", args: [], in: "/tmp") { _, _, _, _ in process }

        XCTAssertNil(output)
        XCTAssertEqual(
            process.waitTimeouts,
            [
                GitHubOperations.probeTimeout,
                GitHubOperations.probeTerminationGrace,
                GitHubOperations.probeTerminationGrace,
            ]
        )
        XCTAssertEqual(process.terminateCallCount, 1)
        XCTAssertEqual(process.forceTerminateCallCount, 1)
    }

    func testTimedOutProbeDoesNotForceTerminateAfterGracefulExit() {
        let process = GitHubReadProcessDouble(waitResults: [false, true])

        let output = GitHubOperations.runCommand("/tmp/slow-git", args: [], in: "/tmp") { _, _, _, _ in process }

        XCTAssertNil(output)
        XCTAssertEqual(process.terminateCallCount, 1)
        XCTAssertEqual(process.forceTerminateCallCount, 0)
    }

    func testProbeFailsClosedOnOutputOverflow() {
        let process = GitHubReadProcessDouble(
            output: Data("partial".utf8),
            outputExceededLimit: true
        )

        let output = GitHubOperations.runCommand("/tmp/noisy-gh", args: [], in: "/tmp") { _, _, _, limit in
            XCTAssertEqual(limit, 256 * 1024)
            return process
        }

        XCTAssertNil(output)
    }

    func testProbeFailsClosedWhenOutputDrainDoesNotFinish() {
        let process = GitHubReadProcessDouble(
            output: Data("partial".utf8),
            didFinishOutput: false
        )

        let output = GitHubOperations.runCommand("/tmp/broken-gh", args: [], in: "/tmp") { _, _, _, _ in process }

        XCTAssertNil(output)
    }

    func testProbeFailsClosedOnNonzeroExitAndInvalidUTF8() {
        let failed = GitHubReadProcessDouble(output: Data("failure".utf8), terminationStatus: 1)
        XCTAssertNil(GitHubOperations.runCommand("/tmp/failed-gh", args: [], in: "/tmp") { _, _, _, _ in failed })

        let invalidUTF8 = GitHubReadProcessDouble(output: Data([0xFF]))
        XCTAssertNil(GitHubOperations.runCommand("/tmp/invalid-gh", args: [], in: "/tmp") { _, _, _, _ in invalidUTF8 })
    }

    func testProbeFailsClosedOnFactoryAndRunFailure() {
        XCTAssertNil(
            GitHubOperations.runCommand("/tmp/missing-gh", args: [], in: "/tmp") { _, _, _, _ in
                throw GitHubReadProbeTestError.launch
            }
        )

        let process = GitHubReadProcessDouble()
        process.runError = GitHubReadProbeTestError.launch
        XCTAssertNil(GitHubOperations.runCommand("/tmp/unlaunchable-gh", args: [], in: "/tmp") { _, _, _, _ in process })
        XCTAssertEqual(process.runCallCount, 1)
    }
}
