// ABOUTME: Compact status strip at the bottom of the sidebar: project/workstream/PR counts
// ABOUTME: plus a Claude usage meter (rolling 5-hour block, with optional % vs plan tier).

import SwiftUI

struct SidebarStatusStrip: View {
    let projectCount: Int
    let workstreamCount: Int
    let openPRCount: Int

    @EnvironmentObject private var usageStore: ClaudeUsageStore
    @AppStorage("dockyard.claudePlanTier") private var planTierRaw = ClaudePlanTier.none.rawValue

    private var planTier: ClaudePlanTier { ClaudePlanTier(rawValue: planTierRaw) ?? .none }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            countsLine
            if usageStore.snapshot.hasData {
                usageLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var countsLine: some View {
        HStack(spacing: 8) {
            countItem(systemImage: "folder", count: projectCount)
            countItem(systemImage: "rectangle.stack", count: workstreamCount)
            if openPRCount > 0 {
                countItem(systemImage: "arrow.triangle.pull", count: openPRCount)
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }

    private func countItem(systemImage: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            Text("\(count)")
        }
    }

    private var usageLine: some View {
        // Refresh the reset countdown roughly every 30s without a manual timer.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.needle")
                Text(usageText(now: context.date))
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
            .help(usageTooltip)
        }
    }

    private func usageText(now: Date) -> String {
        let window = usageStore.snapshot.fiveHour
        var parts: [String] = []

        if let budget = planTier.fiveHourTokenBudget, budget > 0 {
            let remaining = max(0, budget - window.tokens)
            let pct = Int((Double(remaining) / Double(budget) * 100).rounded())
            parts.append(String(format: NSLocalizedString("5h: ~%d%% left", comment: "Claude usage, 5-hour window"), pct))
        } else {
            parts.append(String(format: NSLocalizedString("5h: %@", comment: "Claude usage tokens, 5-hour window"), Self.formatTokens(window.tokens)))
        }

        if let resetAt = window.resetAt, resetAt > now {
            parts.append(String(format: NSLocalizedString("resets in %@", comment: "usage window reset countdown"), Self.formatDuration(resetAt.timeIntervalSince(now))))
        }
        return parts.joined(separator: " · ")
    }

    private var usageTooltip: String {
        let snap = usageStore.snapshot
        let five = String(format: NSLocalizedString("Last 5 hours: %@ tokens", comment: ""), Self.formatTokens(snap.fiveHour.tokens))
        let week = String(format: NSLocalizedString("Last 7 days: %@ tokens", comment: ""), Self.formatTokens(snap.sevenDay.tokens))
        let note = NSLocalizedString("Estimated from local Claude transcripts. Percentages are approximate.", comment: "")
        return "\(five)\n\(week)\n\(note)"
    }

    static func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1000)k" }
        return "\(n)"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }
}
