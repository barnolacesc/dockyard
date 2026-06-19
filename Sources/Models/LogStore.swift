// ABOUTME: Owns live unified-log polling and the bounded list shown by the logs window.
// ABOUTME: Keeps filtering and source access testable independently of SwiftUI.

import Foundation
import SwiftUI

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var lines: [LogLine] = []
    @Published private(set) var errorMessage: String?
    @Published var isFollowing = true

    private let source: (any LogSource)?
    private let maxLines: Int
    private var bookmark: Date?
    private var pollingTask: Task<Void, Never>?

    convenience init(maxLines: Int = 5000) {
        do {
            try self.init(source: OSLogStoreSource(), maxLines: maxLines, errorMessage: nil)
        } catch {
            self.init(source: nil, maxLines: maxLines, errorMessage: error.localizedDescription)
        }
    }

    convenience init(source: any LogSource, maxLines: Int = 5000) {
        self.init(source: source, maxLines: maxLines, errorMessage: nil)
    }

    private init(source: (any LogSource)?, maxLines: Int, errorMessage: String?) {
        self.source = source
        self.maxLines = max(1, maxLines)
        self.errorMessage = errorMessage
    }

    func start() {
        guard pollingTask == nil, source != nil else { return }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.isFollowing {
                    await self.refresh()
                }

                do {
                    try await Task.sleep(for: .seconds(1.5))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        guard let source else { return }
        let currentBookmark = bookmark

        do {
            let fetched = try await Task.detached(priority: .utility) {
                try source.entries(since: currentBookmark)
            }.value
            guard !Task.isCancelled else { return }

            let freshLines = fetched
                .filter { line in
                    guard let currentBookmark else { return true }
                    return line.date > currentBookmark
                }
                .sorted { $0.date < $1.date }

            if let latestDate = fetched.map(\.date).max() {
                bookmark = max(bookmark ?? latestDate, latestDate)
            }

            guard !freshLines.isEmpty else { return }
            lines.append(contentsOf: freshLines)
            if lines.count > maxLines {
                lines.removeFirst(lines.count - maxLines)
            }
        } catch {
            // A later poll may succeed; initialization failures are exposed separately.
        }
    }

    func clear() {
        lines.removeAll(keepingCapacity: true)
    }

    func filtered(search: String, category: String?, minLevel: LogLevel) -> [LogLine] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)

        return lines.filter { line in
            let matchesSearch = query.isEmpty
                || line.category.localizedCaseInsensitiveContains(query)
                || line.message.localizedCaseInsensitiveContains(query)
            let matchesCategory = category == nil || line.category == category
            return matchesSearch && matchesCategory && line.level >= minLevel
        }
    }

    var categories: [String] {
        Array(Set(lines.map(\.category)).sorted())
    }
}
