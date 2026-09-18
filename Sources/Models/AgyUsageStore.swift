// ABOUTME: Observable store for Antigravity CLI usage fetched via `agy -p '/usage'`.
// ABOUTME: Keeps the last good report so transient CLI failures do not blank the sidebar.

import Foundation

@MainActor
final class AgyUsageStore: ObservableObject {
    static let shared = AgyUsageStore()

    @Published private(set) var report: AgyUsageReport?

    /// Whether a probe is currently in flight, so the sidebar can show a loading placeholder
    /// while the selected provider has no data yet.
    @Published private(set) var isRefreshing = false

    private static let minProbeInterval: TimeInterval = 180
    private var lastProbe: Date?

    init() {
        refresh(force: true)
    }

    func refresh(force: Bool = false) {
        let now = Date()
        let doProbe = force || lastProbe == nil || now.timeIntervalSince(lastProbe!) >= Self.minProbeInterval
        guard doProbe, !isRefreshing else { return }

        isRefreshing = true
        lastProbe = now

        Task.detached(priority: .utility) {
            let report = AgyUsageProbe.fetch()
            await MainActor.run {
                if let report { self.report = report }
                self.isRefreshing = false
            }
        }
    }

    var hasAnyData: Bool {
        report != nil
    }
}
