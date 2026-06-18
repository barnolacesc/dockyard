// ABOUTME: Tests parsing of Codex `/status` output into usage limit windows.
// ABOUTME: Verifies Codex percent-left values are adapted to Dockyard percent-used rows.

@testable import Dockyard
import XCTest

final class CodexUsageProbeTests: XCTestCase {
    private let sample = """
    OpenAI Codex (v0.139.0)

    Model:                gpt-5.5 (reasoning high, summaries auto)
    Account:              user@example.com (Plus)

    5h limit:             [##############------] 68% left
                          (resets 01:29 on 19 Jun)
    Weekly limit:         [#################---] 85% left
                          (resets 23:30 on 24 Jun)
    """

    func testParsesLimitRowsAndResetText() {
        let report = CodexUsageProbe.parseText(sample)

        XCTAssertEqual(report?.fiveHour?.percentLeft, 68)
        XCTAssertEqual(report?.fiveHour?.resetText, "01:29 on 19 Jun")
        XCTAssertEqual(report?.week?.percentLeft, 85)
        XCTAssertEqual(report?.week?.resetText, "23:30 on 24 Jun")
    }

    func testParsesModelAndAccount() {
        let report = CodexUsageProbe.parseText(sample)

        XCTAssertEqual(report?.model, "gpt-5.5 (reasoning high, summaries auto)")
        XCTAssertEqual(report?.account, "user@example.com (Plus)")
    }

    func testReturnsNilWhenNoLimitRows() {
        XCTAssertNil(CodexUsageProbe.parseText("Model: gpt-5.5\nNo usage here"))
    }

    func testToleratesANSIEscapeSequences() {
        let text = "\u{001B}[2m5h limit:\u{001B}[0m [####------] \u{001B}[1m68% left\u{001B}[0m\n(resets 01:29 on 19 Jun)"
        let report = CodexUsageProbe.parseText(text)

        XCTAssertEqual(report?.fiveHour?.percentLeft, 68)
        XCTAssertEqual(report?.fiveHour?.resetText, "01:29 on 19 Jun")
    }

    func testConvertsPercentLeftToPercentUsed() {
        XCTAssertEqual(CodexUsageProbe.percentUsed(fromPercentLeft: 68), 32)
        XCTAssertEqual(CodexUsageProbe.percentUsed(fromPercentLeft: 0), 100)
        XCTAssertEqual(CodexUsageProbe.percentUsed(fromPercentLeft: 100), 0)
        XCTAssertEqual(CodexUsageProbe.percentUsed(fromPercentLeft: 140), 0)
    }
}
