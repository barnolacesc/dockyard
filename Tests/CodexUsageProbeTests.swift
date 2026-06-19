// ABOUTME: Tests parsing of the Codex app-server `account/rateLimits/read` JSON-RPC response.
// ABOUTME: Verifies primary/secondary windows map to Dockyard's 5-hour and weekly usage rows.

@testable import Dockyard
import XCTest

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
}
