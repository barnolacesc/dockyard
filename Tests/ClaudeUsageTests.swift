// ABOUTME: Tests Claude usage aggregation: 5-hour block boundaries, 7-day rolling sum,
// ABOUTME: timestamp parsing, and plan-tier budgets.

@testable import Dockyard
import XCTest

final class ClaudeUsageTests: XCTestCase {
    private typealias Entry = ClaudeUsageParser.Entry
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testEmptyEntriesHaveNoData() {
        let snapshot = ClaudeUsageParser.aggregate(entries: [], now: now)
        XCTAssertFalse(snapshot.hasData)
        XCTAssertEqual(snapshot.fiveHour.tokens, 0)
        XCTAssertNil(snapshot.fiveHour.resetAt)
    }

    func testFiveHourBlockSumsRecentEntries() {
        let entries = [
            Entry(time: now.addingTimeInterval(-3600), tokens: 100),
            Entry(time: now.addingTimeInterval(-1800), tokens: 250),
        ]
        let snapshot = ClaudeUsageParser.aggregate(entries: entries, now: now)
        XCTAssertTrue(snapshot.hasData)
        XCTAssertEqual(snapshot.fiveHour.tokens, 350)
        // Block started at the first entry; resets 5h after that.
        let expectedReset = now.addingTimeInterval(-3600 + ClaudeUsageParser.fiveHours)
        XCTAssertEqual(snapshot.fiveHour.resetAt, expectedReset)
    }

    func testGapLongerThanFiveHoursStartsNewBlock() {
        let entries = [
            Entry(time: now.addingTimeInterval(-10 * 3600), tokens: 1000), // old block
            Entry(time: now.addingTimeInterval(-1800), tokens: 200),       // new block (within 5h of now)
        ]
        let snapshot = ClaudeUsageParser.aggregate(entries: entries, now: now)
        // Only the recent block counts toward the active 5-hour window.
        XCTAssertEqual(snapshot.fiveHour.tokens, 200)
    }

    func testActiveBlockEmptyWhenLastEntryOlderThanFiveHours() {
        let entries = [Entry(time: now.addingTimeInterval(-6 * 3600), tokens: 500)]
        let snapshot = ClaudeUsageParser.aggregate(entries: entries, now: now)
        XCTAssertTrue(snapshot.hasData)
        XCTAssertEqual(snapshot.fiveHour.tokens, 0)
        XCTAssertNil(snapshot.fiveHour.resetAt)
    }

    func testSevenDayWindowSumsWithinWindowOnly() {
        let entries = [
            Entry(time: now.addingTimeInterval(-8 * 24 * 3600), tokens: 999), // outside 7d
            Entry(time: now.addingTimeInterval(-2 * 24 * 3600), tokens: 300), // inside 7d
            Entry(time: now.addingTimeInterval(-3600), tokens: 100),          // inside 7d
        ]
        let snapshot = ClaudeUsageParser.aggregate(entries: entries, now: now)
        XCTAssertEqual(snapshot.sevenDay.tokens, 400)
    }

    func testParseTimestampHandlesFractionalAndPlain() {
        XCTAssertNotNil(ClaudeUsageParser.parseTimestamp("2026-06-14T08:15:08.515Z"))
        XCTAssertNotNil(ClaudeUsageParser.parseTimestamp("2026-06-14T08:15:08Z"))
        XCTAssertNil(ClaudeUsageParser.parseTimestamp("not a date"))
    }

    func testPlanTierBudgets() {
        XCTAssertNil(ClaudePlanTier.none.fiveHourTokenBudget)
        XCTAssertNotNil(ClaudePlanTier.pro.fiveHourTokenBudget)
        XCTAssertGreaterThan(
            ClaudePlanTier.max20.fiveHourTokenBudget ?? 0,
            ClaudePlanTier.max5.fiveHourTokenBudget ?? 0
        )
    }
}
