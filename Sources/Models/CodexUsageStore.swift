// ABOUTME: Observable store for Codex usage fetched from the Codex `/status` command.
// ABOUTME: Keeps the last good report so transient CLI failures do not blank the sidebar.

import Foundation

@MainActor
final class CodexUsageStore: ObservableObject {
    static let shared = CodexUsageStore()

    @Published private(set) var report: CodexUsageReport?

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
            let report = CodexUsageProbe.fetch()
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
