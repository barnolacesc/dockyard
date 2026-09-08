// ABOUTME: Tests polling, deduplication, bounded history, and filtering for app logs.
// ABOUTME: Uses an injectable fake so tests do not depend on the macOS unified-log store.

@testable import Dockyard
import Foundation
import XCTest

private final class FakeLogSource: LogSource, @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[LogLine]]
    private(set) var bookmarks: [Date?] = []
    private(set) var limits: [Int] = []

    init(batches: [[LogLine]]) {
        self.batches = batches
    }

    func entries(since bookmark: Date?, limit: Int) throws -> [LogLine] {
        lock.lock()
        defer { lock.unlock() }
        bookmarks.append(bookmark)
        limits.append(limit)
        return batches.isEmpty ? [] : batches.removeFirst()
    }
}

@MainActor
final class LogStoreTests: XCTestCase {
    func testRefreshAppendsNewEntriesAndAdvancesBookmarkWithoutDuplicates() async {
        let first = makeLine(second: 1, category: "app", level: .info, message: "First")
        let second = makeLine(second: 2, category: "git", level: .notice, message: "Second")
        let source = FakeLogSource(batches: [[first], [first, second]])
        let store = LogStore(source: source)

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.lines, [first, second])
        XCTAssertEqual(source.bookmarks.count, 2)
        XCTAssertNil(source.bookmarks[0])
        XCTAssertEqual(source.bookmarks[1], first.date)
        XCTAssertEqual(source.limits, [5000, 5000])
    }

    func testRefreshKeepsNewestLinesAtCapacity() async {
        let lines = (1 ... 4).map {
            makeLine(second: $0, category: "app", level: .info, message: "Line \($0)")
        }
        let source = FakeLogSource(batches: [lines])
        let store = LogStore(source: source, maxLines: 3)

        await store.refresh()

        XCTAssertEqual(store.lines, Array(lines.suffix(3)))
        XCTAssertEqual(source.limits, [3])
    }

    func testRefreshAdvancesBookmarkAcrossAnOverCapacitySourceBatch() async {
        let lines = (1 ... 5).map {
            makeLine(second: $0, category: "app", level: .info, message: "Line \($0)")
        }
        let later = makeLine(second: 6, category: "app", level: .info, message: "Later")
        let source = FakeLogSource(batches: [lines, [lines.last!, later]])
        let store = LogStore(source: source, maxLines: 3)

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.lines, Array(lines.suffix(2)) + [later])
        XCTAssertEqual(source.bookmarks[1], lines.last?.date)
        XCTAssertEqual(source.limits, [3, 3])
    }

    func testBoundedTailKeepsNewestValuesInSourceOrder() {
        var tail = BoundedLogTail<Int>(limit: 3)

        for value in 1 ... 10 {
            tail.append(value)
            XCTAssertLessThanOrEqual(tail.count, 3)
        }

        XCTAssertEqual(tail.values, [8, 9, 10])
    }

    func testBoundedTailPreservesAnExactCapacitySnapshot() {
        var tail = BoundedLogTail<Int>(limit: 3)

        [1, 2, 3].forEach { tail.append($0) }

        XCTAssertEqual(tail.values, [1, 2, 3])
    }

    func testProductionSourceCapsRequestedPollCapacity() {
        XCTAssertEqual(OSLogStoreSource.effectiveLimit(for: 25), 25)
        XCTAssertEqual(
            OSLogStoreSource.effectiveLimit(for: OSLogStoreSource.maximumEntriesPerPoll + 1),
            OSLogStoreSource.maximumEntriesPerPoll
        )
    }

    func testFilteringAppliesSearchCategoryAndMinimumLevel() async {
        let lines = [
            makeLine(second: 1, category: "network", level: .info, message: "Request started"),
            makeLine(second: 2, category: "network", level: .error, message: "Request FAILED"),
            makeLine(second: 3, category: "git", level: .fault, message: "Repository failed"),
            makeLine(second: 4, category: "ui", level: .notice, message: "Button tapped"),
        ]
        let store = LogStore(source: FakeLogSource(batches: [lines]))
        await store.refresh()

        XCTAssertEqual(store.filtered(search: "request", category: nil, minLevel: .debug), Array(lines.prefix(2)))
        XCTAssertEqual(store.filtered(search: "NETWORK", category: nil, minLevel: .debug), Array(lines.prefix(2)))
        XCTAssertEqual(store.filtered(search: "", category: "git", minLevel: .debug), [lines[2]])
        XCTAssertEqual(store.filtered(search: "", category: nil, minLevel: .error), [lines[1], lines[2]])
        XCTAssertEqual(store.filtered(search: "failed", category: "network", minLevel: .error), [lines[1]])
    }

    func testCategoriesAreSortedAndUnique() async {
        let lines = [
            makeLine(second: 1, category: "ui", level: .info, message: "One"),
            makeLine(second: 2, category: "app", level: .info, message: "Two"),
            makeLine(second: 3, category: "ui", level: .info, message: "Three"),
        ]
        let store = LogStore(source: FakeLogSource(batches: [lines]))
        await store.refresh()

        XCTAssertEqual(store.categories, ["app", "ui"])
    }

    func testClearEmptiesVisibleLines() async {
        let store = LogStore(source: FakeLogSource(batches: [[makeLine(second: 1)]]))
        await store.refresh()

        store.clear()

        XCTAssertTrue(store.lines.isEmpty)
    }

    private func makeLine(
        second: Int,
        category: String = "app",
        level: LogLevel = .info,
        message: String = "Message"
    ) -> LogLine {
        LogLine(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", second))!,
            date: Date(timeIntervalSince1970: TimeInterval(second)),
            category: category,
            level: level,
            message: message
        )
    }
}
