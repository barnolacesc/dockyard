// ABOUTME: Tests bounded Claude usage subprocess execution with a deterministic process double.
// ABOUTME: Covers command preservation, output caps, deadlines, failures, and terminal races.

@testable import Dockyard
import Foundation
import XCTest

private final class ClaudeUsageProbeProcessDouble: ClaudeUsageProbeProcess, @unchecked Sendable {
    private(set) var terminateCallCount = 0
    private var outputHandler: (@Sendable (Data) -> Void)?
    private var completion: (@Sendable (Int32) -> Void)?

    func capture(
        outputHandler: @escaping @Sendable (Data) -> Void,
        completion: @escaping @Sendable (Int32) -> Void
    ) {
        self.outputHandler = outputHandler
        self.completion = completion
    }

    func emit(_ data: Data) {
        outputHandler?(data)
    }

    func complete(exitCode: Int32) {
        completion?(exitCode)
    }

    func terminate() {
        terminateCallCount += 1
    }
}

final class ClaudeUsageProbeProcessTests: XCTestCase {
    func testSuccessfulProbePreservesCommandAndParsesBoundedOutput() {
        let process = ClaudeUsageProbeProcessDouble()
        let payload = Data(#"{"result":"Current session: 20% used · resets in 1h"}"#.utf8)

        let report = ClaudeUsageProbe.fetch(
            shell: "/bin/zsh",
            timeout: 1,
            processFactory: { executableURL, arguments, workingDirectoryURL, outputHandler, completion in
                XCTAssertEqual(executableURL.path, "/bin/zsh")
                XCTAssertEqual(arguments, ["-lic", "claude -p '/usage' --output-format json"])
                XCTAssertEqual(workingDirectoryURL, FileManager.default.homeDirectoryForCurrentUser)
                process.capture(outputHandler: outputHandler, completion: completion)
                process.emit(payload)
                process.complete(exitCode: 0)
                return process
            }
        )

        XCTAssertEqual(report?.session?.percentUsed, 20)
        XCTAssertEqual(report?.session?.resetText, "in 1h")
        XCTAssertEqual(process.terminateCallCount, 0)
    }

    func testOutputCollectorContinuouslyDrainsButRetainsOnlyTheFixedCap() {
        let operation = ClaudeUsageProbeOperation(maximumOutputBytes: 4)

        operation.ingest(Data("abc".utf8))
        operation.ingest(Data("def".utf8))

        XCTAssertEqual(operation.bufferedOutputByteCount, 4)
        XCTAssertTrue(operation.complete(exitCode: 0))
        XCTAssertEqual(operation.outcome, .completed(output: Data("abcd".utf8), exitCode: 0))

        operation.ingest(Data("ignored".utf8))
        XCTAssertEqual(operation.bufferedOutputByteCount, 4)
    }

    func testTimedOutProbeTerminatesAndReturnsNoReport() {
        let process = ClaudeUsageProbeProcessDouble()

        let report = ClaudeUsageProbe.fetch(
            shell: "/bin/zsh",
            timeout: 0.01,
            processFactory: { _, _, _, outputHandler, completion in
                process.capture(outputHandler: outputHandler, completion: completion)
                return process
            }
        )

        XCTAssertNil(report)
        XCTAssertEqual(process.terminateCallCount, 1)
    }

    func testNonzeroExitReturnsNoReport() {
        let process = ClaudeUsageProbeProcessDouble()

        let report = ClaudeUsageProbe.fetch(
            timeout: 1,
            processFactory: { _, _, _, outputHandler, completion in
                process.capture(outputHandler: outputHandler, completion: completion)
                process.emit(Data(#"{"result":"Current week: 12% used"}"#.utf8))
                process.complete(exitCode: 7)
                return process
            }
        )

        XCTAssertNil(report)
        XCTAssertEqual(process.terminateCallCount, 0)
    }

    func testLaunchFailureReturnsNoReport() {
        enum LaunchError: Error { case unavailable }

        let report = ClaudeUsageProbe.fetch(
            timeout: 1,
            processFactory: { _, _, _, _, _ in throw LaunchError.unavailable }
        )

        XCTAssertNil(report)
    }

    func testOperationPublishesOnlyTheFirstTerminalOutcome() {
        let operation = ClaudeUsageProbeOperation(maximumOutputBytes: 32)
        operation.ingest(Data("result".utf8))

        XCTAssertTrue(operation.timeOut())
        XCTAssertFalse(operation.complete(exitCode: 0))
        XCTAssertFalse(operation.timeOut())
        XCTAssertEqual(operation.outcome, .timedOut)
    }
}
