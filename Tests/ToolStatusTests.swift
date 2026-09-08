// ABOUTME: Verifies startup tool probes have deterministic process and output boundaries.
// ABOUTME: Keeps broken local CLIs from stalling Dockyard tool detection.

@testable import Dockyard
import Foundation
import XCTest

private final class ToolProbeProcessDouble: ToolProbeProcess, @unchecked Sendable {
    var result: ToolProbeProcessResult
    var waitResults: [Bool]
    private(set) var runCallCount = 0
    private(set) var waitTimeouts: [TimeInterval] = []
    private(set) var terminateCallCount = 0
    private(set) var forceTerminateCallCount = 0

    init(
        output: String = "",
        terminationStatus: Int32 = 0,
        outputExceededLimit: Bool = false,
        waitResults: [Bool] = [true]
    ) {
        result = ToolProbeProcessResult(
            output: Data(output.utf8),
            terminationStatus: terminationStatus,
            outputExceededLimit: outputExceededLimit
        )
        self.waitResults = waitResults
    }

    func run() throws {
        runCallCount += 1
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

final class ToolStatusTests: XCTestCase {
    func testVersionProbeUsesBoundedProcessAndNormalizesVersion() {
        let process = ToolProbeProcessDouble(output: "codex-cli 1.2.3\nignored")
        let version = ToolStatus.runForVersion("/opt/homebrew/bin/codex", args: ["--version"]) {
            executableURL,
            arguments,
            includeStderr,
            maximumOutputBytes in
            XCTAssertEqual(executableURL.path, "/opt/homebrew/bin/codex")
            XCTAssertEqual(arguments, ["--version"])
            XCTAssertFalse(includeStderr)
            XCTAssertEqual(maximumOutputBytes, ToolStatus.maximumProbeOutputBytes)
            return process
        }

        XCTAssertEqual(version, "1.2.3")
        XCTAssertEqual(process.runCallCount, 1)
        XCTAssertEqual(process.waitTimeouts, [ToolStatus.probeTimeout])
        XCTAssertEqual(process.terminateCallCount, 0)
    }

    func testHelpProbeIncludesStderrAndFindsFlag() {
        let process = ToolProbeProcessDouble(output: "usage: claude [--name value]", terminationStatus: 2)
        let supportsName = ToolStatus.helpContainsFlag("/usr/local/bin/claude", flag: "--name") {
            _,
            arguments,
            includeStderr,
            _ in
            XCTAssertEqual(arguments, ["--help"])
            XCTAssertTrue(includeStderr)
            return process
        }

        XCTAssertTrue(supportsName)
    }

    func testTimedOutProbeTerminatesThenForceTerminates() {
        let process = ToolProbeProcessDouble(waitResults: [false, false, true])
        let output = ToolStatus.runCommand("/tmp/hung-cli", args: ["--version"]) { _, _, _, _ in process }

        XCTAssertNil(output)
        XCTAssertEqual(
            process.waitTimeouts,
            [
                ToolStatus.probeTimeout,
                ToolStatus.probeTerminationGrace,
                ToolStatus.probeTerminationGrace,
            ]
        )
        XCTAssertEqual(process.terminateCallCount, 1)
        XCTAssertEqual(process.forceTerminateCallCount, 1)
    }

    func testTimedOutProbeDoesNotForceTerminateAfterGracefulExit() {
        let process = ToolProbeProcessDouble(waitResults: [false, true])
        let output = ToolStatus.runCommand("/tmp/slow-cli", args: ["--version"]) { _, _, _, _ in process }

        XCTAssertNil(output)
        XCTAssertEqual(process.terminateCallCount, 1)
        XCTAssertEqual(process.forceTerminateCallCount, 0)
    }

    func testOversizedProbeOutputFailsClosed() {
        let process = ToolProbeProcessDouble(output: "partial", outputExceededLimit: true)
        let output = ToolStatus.runCommand("/tmp/noisy-cli", args: ["--version"]) { _, _, _, limit in
            XCTAssertEqual(limit, 64 * 1024)
            return process
        }

        XCTAssertNil(output)
    }

    func testFailedVersionProbeReturnsNil() {
        let process = ToolProbeProcessDouble(output: "broken", terminationStatus: 1)
        let version = ToolStatus.runForVersion("/tmp/broken-cli", args: ["--version"]) { _, _, _, _ in process }

        XCTAssertNil(version)
    }
}
