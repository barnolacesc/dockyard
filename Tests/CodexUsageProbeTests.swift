// ABOUTME: Tests parsing of the Codex app-server `account/rateLimits/read` JSON-RPC response.
// ABOUTME: Verifies primary/secondary windows map to Dockyard's 5-hour and weekly usage rows.

@testable import Dockyard
import Foundation
import XCTest

private enum CodexUsageProbeTestError: Error {
    case launch
}

private final class CodexUsageProbeProcessDouble: CodexUsageProbeProcess, @unchecked Sendable {
    private var outputHandler: (@Sendable (Data) -> Void)?
    private var errorHandler: (@Sendable (Data) -> Void)?
    var onWrite: (() -> Void)?
    private(set) var input = Data()
    private(set) var closeInputCallCount = 0
    private(set) var terminateCallCount = 0
    private(set) var deliveredErrorByteCount = 0

    func capture(
        outputHandler: @escaping @Sendable (Data) -> Void,
        errorHandler: @escaping @Sendable (Data) -> Void
    ) {
        self.outputHandler = outputHandler
        self.errorHandler = errorHandler
    }

    func emitOutput(_ data: Data) {
        outputHandler?(data)
    }

    func emitError(_ data: Data) {
        deliveredErrorByteCount += data.count
        errorHandler?(data)
    }

    func writeToStandardInput(_ data: Data) {
        input.append(data)
        onWrite?()
    }

    func closeStandardInput() {
        closeInputCallCount += 1
    }

    func terminate() {
        terminateCallCount += 1
    }
}

final class CodexUsageProbeTests: XCTestCase {
    private let sample = Data("""
    {"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":33,"windowDurationMins":300,"resetsAt":1781918988},"secondary":{"usedPercent":36,"windowDurationMins":10080,"resetsAt":1782336604},"planType":"plus"}}}
    """.utf8)

    func testParsesPrimaryAndSecondaryWindows() {
        let report = CodexUsageProbe.parseRateLimits(sample)

        XCTAssertEqual(report?.fiveHour?.usedPercent, 33)
        XCTAssertEqual(report?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_781_918_988))
        XCTAssertEqual(report?.week?.usedPercent, 36)
        XCTAssertEqual(report?.week?.resetsAt, Date(timeIntervalSince1970: 1_782_336_604))
        XCTAssertEqual(report?.planType, "plus")
    }

    func testParsesWhenSecondaryWindowMissing() {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":10}}}}"#.utf8)
        let report = CodexUsageProbe.parseRateLimits(data)

        XCTAssertEqual(report?.fiveHour?.usedPercent, 10)
        XCTAssertNil(report?.fiveHour?.resetsAt)
        XCTAssertNil(report?.week)
    }

    func testClampsUsedPercentToValidRange() {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":140},"secondary":{"usedPercent":-5}}}}"#.utf8)
        let report = CodexUsageProbe.parseRateLimits(data)

        XCTAssertEqual(report?.fiveHour?.usedPercent, 100)
        XCTAssertEqual(report?.week?.usedPercent, 0)
    }

    func testReturnsNilForLinesWithoutRateLimits() {
        XCTAssertNil(CodexUsageProbe.parseRateLimits(Data(#"{"id":1,"result":{}}"#.utf8)))
        XCTAssertNil(CodexUsageProbe.parseRateLimits(Data(#"{"method":"thread/started","params":{}}"#.utf8)))
        XCTAssertNil(CodexUsageProbe.parseRateLimits(Data("not json at all".utf8)))
    }

    func testReturnsNilWhenBothWindowsMissing() {
        let data = Data(#"{"id":2,"result":{"rateLimits":{"planType":"plus"}}}"#.utf8)
        XCTAssertNil(CodexUsageProbe.parseRateLimits(data))
    }

    func testProbePreservesCommandRequestsAndParsesChunkedOutput() {
        let process = CodexUsageProbeProcessDouble()
        process.onWrite = {
            process.emitOutput(Data(#"{"id":1,"result":{}}"#.utf8))
            process.emitOutput(Data("\n".utf8))
            process.emitOutput(self.sample.prefix(23))
            process.emitOutput(self.sample.dropFirst(23))
            process.emitOutput(Data("\n".utf8))
        }

        let report = CodexUsageProbe.fetch(
            shell: "/bin/zsh",
            timeout: 1,
            processFactory: { executableURL, arguments, workingDirectoryURL, outputHandler, errorHandler in
                XCTAssertEqual(executableURL.path, "/bin/zsh")
                XCTAssertEqual(arguments, ["-lic", "codex app-server"])
                XCTAssertEqual(workingDirectoryURL, FileManager.default.homeDirectoryForCurrentUser)
                process.capture(outputHandler: outputHandler, errorHandler: errorHandler)
                return process
            }
        )

        XCTAssertEqual(report?.fiveHour?.usedPercent, 33)
        XCTAssertEqual(report?.week?.usedPercent, 36)
        XCTAssertEqual(
            String(data: process.input, encoding: .utf8),
            """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"dockyard","version":"1.0"},"capabilities":{"experimentalApi":true}}}
            {"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}

            """
        )
        XCTAssertEqual(process.closeInputCallCount, 1)
        XCTAssertEqual(process.terminateCallCount, 1)
    }

    func testCollectorAcceptsAValidLineAtTheExactByteLimit() {
        XCTAssertEqual(CodexUsageProbe.maximumResponseLineBytes, 64 * 1024)
        let collector = CodexUsageResponseCollector(
            maximumLineBytes: CodexUsageProbe.maximumResponseLineBytes
        )
        var payload = sample
        payload.append(
            Data(
                repeating: 0x20,
                count: CodexUsageProbe.maximumResponseLineBytes - sample.count
            )
        )
        payload.append(0x0A)

        XCTAssertTrue(collector.ingest(payload))
        XCTAssertEqual(collector.report?.fiveHour?.usedPercent, 33)
        XCTAssertEqual(collector.bufferedByteCount, 0)
        XCTAssertFalse(collector.isDiscardingOversizedLine)
    }

    func testCollectorBoundsAndDiscardsAnOversizedLineThenRecovers() {
        let collector = CodexUsageResponseCollector(maximumLineBytes: sample.count)

        XCTAssertFalse(collector.ingest(Data(repeating: 0x78, count: sample.count + 1)))
        XCTAssertEqual(collector.bufferedByteCount, 0)
        XCTAssertTrue(collector.isDiscardingOversizedLine)

        var recovery = Data([0x0A])
        recovery.append(sample)
        recovery.append(0x0A)
        XCTAssertTrue(collector.ingest(recovery))
        XCTAssertEqual(collector.report?.planType, "plus")
        XCTAssertEqual(collector.bufferedByteCount, 0)
        XCTAssertFalse(collector.isDiscardingOversizedLine)
    }

    func testCollectorPublishesOnlyTheFirstValidResponse() {
        let collector = CodexUsageResponseCollector(maximumLineBytes: sample.count)
        var payload = sample
        payload.append(0x0A)

        XCTAssertTrue(collector.ingest(payload))
        XCTAssertFalse(collector.ingest(payload))
        XCTAssertEqual(collector.report?.fiveHour?.usedPercent, 33)
    }

    func testProbeDrainsStderrWithoutRetainingItInTheReport() {
        let process = CodexUsageProbeProcessDouble()
        process.onWrite = {
            process.emitError(Data(repeating: 0x65, count: 128 * 1024))
            var payload = self.sample
            payload.append(0x0A)
            process.emitOutput(payload)
        }

        let report = CodexUsageProbe.fetch(timeout: 1) {
            _, _, _, outputHandler, errorHandler in
            process.capture(outputHandler: outputHandler, errorHandler: errorHandler)
            return process
        }

        XCTAssertEqual(process.deliveredErrorByteCount, 128 * 1024)
        XCTAssertEqual(report?.planType, "plus")
    }

    func testProbeLaunchFailureReturnsNil() {
        let report = CodexUsageProbe.fetch(timeout: 1) {
            _, _, _, _, _ in throw CodexUsageProbeTestError.launch
        }

        XCTAssertNil(report)
    }

    func testTimedOutProbeClosesInputAndTerminates() {
        let process = CodexUsageProbeProcessDouble()

        let report = CodexUsageProbe.fetch(timeout: 0.01) {
            _, _, _, outputHandler, errorHandler in
            process.capture(outputHandler: outputHandler, errorHandler: errorHandler)
            return process
        }

        XCTAssertNil(report)
        XCTAssertEqual(process.closeInputCallCount, 1)
        XCTAssertEqual(process.terminateCallCount, 1)
    }
}
