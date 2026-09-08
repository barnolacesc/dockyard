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
    func testSuccessfulCountPreservesGitCommandAndWorkingDirectory() {
        let process = UpdateCheckProcessDouble(output: Data("  42\n".utf8))

        let count = UpdateCheckCommandRunner.commitsAhead(at: "/tmp/dockyard source") {
            executableURL,
            arguments,
            workingDirectoryURL,
            maximumOutputBytes in
            XCTAssertEqual(executableURL.path, "/usr/bin/git")
            XCTAssertEqual(arguments, ["rev-list", "--count", "HEAD..origin/main"])
            XCTAssertEqual(workingDirectoryURL.path, "/tmp/dockyard source")
            XCTAssertEqual(maximumOutputBytes, 64 * 1024)
            return process
        }

        XCTAssertEqual(count, 42)
        XCTAssertEqual(process.runCallCount, 1)
        XCTAssertEqual(process.waitCallCount, 1)
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
        XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp") { _, _, _, _ in overflow })

        let incomplete = UpdateCheckProcessDouble(
            output: Data("1".utf8),
            didFinishOutput: false
        )
        XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp") { _, _, _, _ in incomplete })

        let failed = UpdateCheckProcessDouble(
            output: Data("1".utf8),
            terminationStatus: 1
        )
        XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp") { _, _, _, _ in failed })
    }

    func testFailsClosedOnMalformedInvalidAndNegativeOutput() {
        for output in [Data("many".utf8), Data([0xFF]), Data("-1".utf8)] {
            let process = UpdateCheckProcessDouble(output: output)
            XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp") { _, _, _, _ in process })
        }
    }

    func testFailsClosedOnFactoryAndLaunchFailureWithoutWaiting() {
        XCTAssertNil(
            UpdateCheckCommandRunner.commitsAhead(at: "/tmp") { _, _, _, _ in
                throw UpdateCheckTestError.launch
            }
        )

        let process = UpdateCheckProcessDouble()
        process.runError = UpdateCheckTestError.launch
        XCTAssertNil(UpdateCheckCommandRunner.commitsAhead(at: "/tmp") { _, _, _, _ in process })
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
