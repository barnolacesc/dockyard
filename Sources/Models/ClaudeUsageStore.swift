// ABOUTME: Observable store for Claude usage. Prefers the real `/usage` report (via
// ABOUTME: ClaudeUsageProbe) and keeps the local-transcript estimate as a fallback.

import Foundation

@MainActor
final class ClaudeUsageStore: ObservableObject {
    static let shared = ClaudeUsageStore()

    /// Local-transcript estimate (instant, free, Claude Code CLI only). Fallback.
    @Published private(set) var snapshot = ClaudeUsageSnapshot()
    /// Authoritative figures from `claude -p /usage` when available.
    @Published private(set) var report: ClaudeUsageReport?

    /// The cheap local estimate may refresh often; the probe spawns a `claude` process so it
    /// runs far less frequently (but always on an explicit, forced refresh — e.g. a click).
    /// Whether a refresh is currently in flight, so the sidebar can show a loading placeholder
    /// while the selected provider has no data yet.
    @Published private(set) var isRefreshing = false

    private static let minEstimateInterval: TimeInterval = 60
    private static let minProbeInterval: TimeInterval = 180
    private var lastEstimate: Date?
    private var lastProbe: Date?

    init() {
        refresh(force: true)
    }

    /// Recompute usage off the main actor. The local estimate is throttled to
    /// `minEstimateInterval`; the `/usage` probe to `minProbeInterval`. `force` (e.g. a user
    /// click) bypasses both throttles.
    func refresh(force: Bool = false) {
        let now = Date()
        let doEstimate = force || lastEstimate == nil || now.timeIntervalSince(lastEstimate!) >= Self.minEstimateInterval
        let doProbe = force || lastProbe == nil || now.timeIntervalSince(lastProbe!) >= Self.minProbeInterval
        guard doEstimate || doProbe, !isRefreshing else { return }

        isRefreshing = true
        if doEstimate { lastEstimate = now }
        if doProbe { lastProbe = now }

        Task.detached(priority: .utility) {
            let snapshot = doEstimate ? ClaudeUsageParser.compute() : nil
            let report = doProbe ? ClaudeUsageProbe.fetch() : nil
            await MainActor.run {
                if let snapshot { self.snapshot = snapshot }
                // Keep the last good report if a probe transiently fails.
                if let report { self.report = report }
                self.isRefreshing = false
            }
        }
    }

    /// Whether there's anything to show (real report or local estimate).
    var hasAnyData: Bool {
        report != nil || snapshot.hasData
    }
}
