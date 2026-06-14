// ABOUTME: Tests parsing of `claude -p /usage` output into session/week usage figures.

@testable import Dockyard
import XCTest

final class ClaudeUsageProbeTests: XCTestCase {
    func testParsesSessionAndWeek() {
        let text = """
        You are currently using your subscription to power your Claude Code usage

        Current session: 63% used · resets Jun 14 at 3pm (Europe/Madrid)
        Current week (all models): 43% used · resets Jun 17 at 9am (Europe/Madrid)
        """
        let report = ClaudeUsageProbe.parseText(text)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.session?.percentUsed, 63)
        XCTAssertEqual(report?.session?.resetText, "Jun 14 at 3pm")
        XCTAssertEqual(report?.week?.percentUsed, 43)
        XCTAssertEqual(report?.week?.resetText, "Jun 17 at 9am")
    }

    func testParsesJSONEnvelope() {
        let json = #"{"type":"result","result":"Current session: 10% used · resets Jun 1 at 5pm (UTC)\nCurrent week (all models): 5% used · resets Jun 7 at 8am (UTC)"}"#
        let report = ClaudeUsageProbe.parse(Data(json.utf8))
        XCTAssertEqual(report?.session?.percentUsed, 10)
        XCTAssertEqual(report?.week?.percentUsed, 5)
    }

    func testReturnsNilWhenNoUsageLines() {
        XCTAssertNil(ClaudeUsageProbe.parseText("Some unrelated output with no percentages."))
    }

    func testHandlesMissingTimezoneParenthetical() {
        let report = ClaudeUsageProbe.parseText("Current session: 80% used · resets in 2h")
        XCTAssertEqual(report?.session?.percentUsed, 80)
        XCTAssertEqual(report?.session?.resetText, "in 2h")
    }
}
