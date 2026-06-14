// ABOUTME: Observable store that periodically recomputes Claude usage from local transcripts
// ABOUTME: and publishes a snapshot for the sidebar usage meter.

import Foundation

@MainActor
final class ClaudeUsageStore: ObservableObject {
    static let shared = ClaudeUsageStore()

    @Published private(set) var snapshot = ClaudeUsageSnapshot()

    /// Parsing reads every recent transcript, so throttle refreshes even when callers (e.g.
    /// the 15s poll) ask more often.
    private static let minRefreshInterval: TimeInterval = 60
    private var lastRefresh: Date?
    private var isRefreshing = false

    init() {
        refresh()
    }

    /// Recompute the snapshot off the main actor. No-op if refreshed within the throttle
    /// interval, unless `force` is set.
    func refresh(force: Bool = false) {
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < Self.minRefreshInterval {
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefresh = Date()
        Task.detached(priority: .utility) {
            let snapshot = ClaudeUsageParser.compute()
            await MainActor.run {
                self.snapshot = snapshot
                self.isRefreshing = false
            }
        }
    }
}
