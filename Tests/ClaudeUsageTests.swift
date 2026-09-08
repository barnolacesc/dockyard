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

    func testParseEntriesReadsRecentRegularTranscript() throws {
        let root = temporaryTranscriptDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transcript = root.appendingPathComponent("session.jsonl")
        try Data(transcriptLine(inputTokens: 120, outputTokens: 30).utf8).write(to: transcript)

        let entries = ClaudeUsageParser.parseEntries(in: root, since: .distantPast)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.tokens, 150)
    }

    func testParseEntriesSkipsTranscriptOlderThanHorizon() throws {
        let root = temporaryTranscriptDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transcript = root.appendingPathComponent("session.jsonl")
        try Data(transcriptLine(inputTokens: 120, outputTokens: 30).utf8).write(to: transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: transcript.path
        )

        let entries = ClaudeUsageParser.parseEntries(
            in: root,
            since: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertTrue(entries.isEmpty)
    }

    func testParseEntriesRejectsSymbolicLinkTranscript() throws {
        let root = temporaryTranscriptDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("outside.json")
        let link = root.appendingPathComponent("session.jsonl")
        try Data(transcriptLine(inputTokens: 500, outputTokens: 25).utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertTrue(ClaudeUsageParser.parseEntries(in: root, since: .distantPast).isEmpty)
    }

    func testParseEntriesRejectsNonRegularTranscript() throws {
        let root = temporaryTranscriptDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("session.jsonl", isDirectory: true),
            withIntermediateDirectories: false
        )

        XCTAssertTrue(ClaudeUsageParser.parseEntries(in: root, since: .distantPast).isEmpty)
    }

    func testParseEntriesRejectsOversizedTranscript() throws {
        let root = temporaryTranscriptDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transcript = root.appendingPathComponent("session.jsonl")
        XCTAssertTrue(FileManager.default.createFile(atPath: transcript.path, contents: nil))
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.truncate(atOffset: UInt64(ClaudeUsageParser.maximumTranscriptBytes + 1))
        try handle.close()

        XCTAssertTrue(ClaudeUsageParser.parseEntries(in: root, since: .distantPast).isEmpty)
    }

    func testParseEntriesSkipsOversizedLineAndKeepsFollowingRecord() throws {
        let root = temporaryTranscriptDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transcript = root.appendingPathComponent("session.jsonl")
        var data = Data(repeating: 0x78, count: ClaudeUsageParser.maximumLineBytes + 1)
        data.append(0x0A)
        data.append(Data(transcriptLine(inputTokens: 70, outputTokens: 5).utf8))
        try data.write(to: transcript)

        let entries = ClaudeUsageParser.parseEntries(in: root, since: .distantPast)

        XCTAssertEqual(entries.map(\.tokens), [75])
    }

    func testPlanTierBudgets() {
        XCTAssertNil(ClaudePlanTier.none.fiveHourTokenBudget)
        XCTAssertNotNil(ClaudePlanTier.pro.fiveHourTokenBudget)
        XCTAssertGreaterThan(
            ClaudePlanTier.max20.fiveHourTokenBudget ?? 0,
            ClaudePlanTier.max5.fiveHourTokenBudget ?? 0
        )
    }

    private func temporaryTranscriptDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-claude-usage-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func transcriptLine(inputTokens: Int, outputTokens: Int) -> String {
        """
        {"timestamp":"2026-08-28T14:30:00Z","message":{"usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens)}}}
        """
    }
}
