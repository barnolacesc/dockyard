// ABOUTME: Defines the injectable source used by the in-app logs store.
// ABOUTME: Reads bounded snapshots from the current process's unified log.

import Foundation
import OSLog

protocol LogSource: Sendable {
    func entries(since bookmark: Date?, limit: Int) throws -> [LogLine]
}

final class OSLogStoreSource: LogSource, @unchecked Sendable {
    private static let initialHistoryInterval: TimeInterval = 5 * 60
    static let maximumEntriesPerPoll = 5000

    init() throws {
        _ = try OSLogStore(scope: .currentProcessIdentifier)
    }

    func entries(since bookmark: Date?, limit: Int) throws -> [LogLine] {
        // OSLogStore instances represent fixed snapshots, so each poll needs a fresh store.
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let startDate = bookmark ?? Date().addingTimeInterval(-Self.initialHistoryInterval)
        let position = store.position(date: startDate)
        let predicate = NSPredicate(format: "subsystem == %@", "dockyard")
        let entries = try store.getEntries(at: position, matching: predicate)
        var snapshot = BoundedLogTail<LogLine>(limit: Self.effectiveLimit(for: limit))

        for case let entry as OSLogEntryLog in entries {
            snapshot.append(LogLine(
                date: entry.date,
                category: entry.category,
                level: LogLevel(from: entry.level),
                message: entry.composedMessage
            ))
        }

        return snapshot.values
    }

    static func effectiveLimit(for requestedLimit: Int) -> Int {
        min(max(1, requestedLimit), maximumEntriesPerPoll)
    }
}

struct BoundedLogTail<Element> {
    private let limit: Int
    private var storage: [Element] = []
    private var replacementIndex = 0

    init(limit: Int) {
        self.limit = max(1, limit)
        storage.reserveCapacity(self.limit)
    }

    var count: Int {
        storage.count
    }

    mutating func append(_ element: Element) {
        guard storage.count == limit else {
            storage.append(element)
            return
        }

        storage[replacementIndex] = element
        replacementIndex = (replacementIndex + 1) % limit
    }

    var values: [Element] {
        guard storage.count == limit, replacementIndex != 0 else {
            return storage
        }

        var ordered: [Element] = []
        ordered.reserveCapacity(storage.count)
        ordered.append(contentsOf: storage[replacementIndex...])
        ordered.append(contentsOf: storage[..<replacementIndex])
        return ordered
    }
}
