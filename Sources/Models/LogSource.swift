// ABOUTME: Defines the injectable source used by the in-app logs store.
// ABOUTME: Reads bounded snapshots from the current process's unified log.

import Foundation
import OSLog

protocol LogSource: Sendable {
    func entries(since bookmark: Date?) throws -> [LogLine]
}

final class OSLogStoreSource: LogSource, @unchecked Sendable {
    private static let initialHistoryInterval: TimeInterval = 5 * 60

    init() throws {
        _ = try OSLogStore(scope: .currentProcessIdentifier)
    }

    func entries(since bookmark: Date?) throws -> [LogLine] {
        // OSLogStore instances represent fixed snapshots, so each poll needs a fresh store.
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let startDate = bookmark ?? Date().addingTimeInterval(-Self.initialHistoryInterval)
        let position = store.position(date: startDate)
        let predicate = NSPredicate(format: "subsystem == %@", "dockyard")
        let entries = try store.getEntries(at: position, matching: predicate)

        return entries.compactMap { entry in
            guard let entry = entry as? OSLogEntryLog else { return nil }
            return LogLine(
                date: entry.date,
                category: entry.category,
                level: LogLevel(from: entry.level),
                message: entry.composedMessage
            )
        }
    }
}
