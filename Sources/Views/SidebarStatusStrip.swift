// ABOUTME: Status strip at the bottom of the sidebar: a Claude usage meter (Current 5-hour
// ABOUTME: block + Weekly 7-day window with % bars) plus a thin project/workstream/PR count line.

import SwiftUI

struct SidebarStatusStrip: View {
    let projectCount: Int
    let workstreamCount: Int
    let openPRCount: Int
    var waitingCount: Int = 0

    @EnvironmentObject private var usageStore: ClaudeUsageStore
    @AppStorage("dockyard.claudePlanTier") private var planTierRaw = ClaudePlanTier.none.rawValue

    private var planTier: ClaudePlanTier { ClaudePlanTier(rawValue: planTierRaw) ?? .none }

    /// Lime green for the weekly bar, to contrast with the orange 5-hour bar.
    private static let weeklyTint = Color(red: 0.62, green: 0.80, blue: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if usageStore.hasAnyData {
                usageMeter
            }
            countsLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Usage meter

    private var usageMeter: some View {
        // Recompute the reset countdown roughly every 30s without a manual timer.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.needle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Usage")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)

                currentRow(now: context.date)
                weeklyRow
            }
            .contentShape(Rectangle())
            .onTapGesture { usageStore.refresh(force: true) }
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help(usageTooltip)
        }
    }

    /// Current (5-hour) window. Prefers the real `/usage` figure, falls back to the estimate.
    private func currentRow(now: Date) -> UsageMeterRow {
        let label = NSLocalizedString("Current", comment: "Claude 5-hour usage window")
        if let session = usageStore.report?.session {
            return UsageMeterRow(
                headline: "\(session.percentUsed)%",
                label: label,
                tint: .orange,
                fraction: Double(session.percentUsed) / 100,
                subtitle: session.resetText.map(Self.resetsString)
            )
        }
        let window = usageStore.snapshot.fiveHour
        return UsageMeterRow(
            headline: estimateHeadline(tokens: window.tokens, budget: planTier.fiveHourTokenBudget),
            label: label,
            tint: .orange,
            fraction: fraction(tokens: window.tokens, budget: planTier.fiveHourTokenBudget),
            subtitle: estimateResetSubtitle(window.resetAt, now: now)
        )
    }

    /// Weekly (7-day) window. Prefers the real `/usage` figure, falls back to the estimate.
    private var weeklyRow: UsageMeterRow {
        let label = NSLocalizedString("Weekly", comment: "Claude 7-day usage window")
        if let week = usageStore.report?.week {
            return UsageMeterRow(
                headline: "\(week.percentUsed)%",
                label: label,
                tint: Self.weeklyTint,
                fraction: Double(week.percentUsed) / 100,
                subtitle: week.resetText.map(Self.resetsString)
            )
        }
        let window = usageStore.snapshot.sevenDay
        return UsageMeterRow(
            headline: estimateHeadline(tokens: window.tokens, budget: planTier.weeklyTokenBudget),
            label: label,
            tint: Self.weeklyTint,
            fraction: fraction(tokens: window.tokens, budget: planTier.weeklyTokenBudget),
            subtitle: NSLocalizedString("rolling 7 days", comment: "Claude weekly usage window")
        )
    }

    private func fraction(tokens: Int, budget: Int?) -> Double {
        guard let budget, budget > 0 else { return 0 }
        return min(1, Double(tokens) / Double(budget))
    }

    private func estimateHeadline(tokens: Int, budget: Int?) -> String {
        guard let budget, budget > 0 else { return Self.formatTokens(tokens) }
        return "\(Int((min(1, Double(tokens) / Double(budget)) * 100).rounded()))%"
    }

    private func estimateResetSubtitle(_ resetAt: Date?, now: Date) -> String? {
        guard let resetAt, resetAt > now else { return nil }
        return String(
            format: NSLocalizedString("resets in %@", comment: "usage window reset countdown"),
            Self.formatDuration(resetAt.timeIntervalSince(now))
        )
    }

    private static func resetsString(_ text: String) -> String {
        String(format: NSLocalizedString("resets %@", comment: "usage window reset time"), text)
    }

    private var usageTooltip: String {
        if usageStore.report != nil {
            return NSLocalizedString("Real usage from Claude Code's /usage. Click to refresh.", comment: "")
        }
        let snap = usageStore.snapshot
        let five = String(format: NSLocalizedString("Last 5 hours: %@ tokens", comment: ""), Self.formatTokens(snap.fiveHour.tokens))
        let week = String(format: NSLocalizedString("Last 7 days: %@ tokens", comment: ""), Self.formatTokens(snap.sevenDay.tokens))
        let note = NSLocalizedString("Estimated from local Claude Code transcripts (CLI only, not your full account). Percentages are approximate.", comment: "")
        return "\(five)\n\(week)\n\(note)"
    }

    // MARK: - Counts

    private var countsLine: some View {
        HStack(spacing: 8) {
            countItem(systemImage: "folder", count: projectCount)
            countItem(systemImage: "rectangle.stack", count: workstreamCount)
            if openPRCount > 0 {
                countItem(systemImage: "arrow.triangle.pull", count: openPRCount)
            }
            if waitingCount > 0 {
                countItem(systemImage: "bell.fill", count: waitingCount)
                    .foregroundStyle(Color.accentColor)
                    .help(NSLocalizedString("Agents waiting on you", comment: ""))
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

    // MARK: - Formatting

    static func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1000)k" }
        return "\(n)"
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

/// One row of the usage meter: a big headline (% or token count), a window label pill, a
/// filling colored bar, and a small subtitle.
private struct UsageMeterRow: View {
    let headline: String
    let label: String
    let tint: Color
    let fraction: Double
    let subtitle: String?

    /// Shift toward red as the window approaches its limit.
    private var barTint: Color {
        fraction >= 0.9 ? .red : tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(headline)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            UsageBar(fraction: fraction, tint: barTint)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// A rounded progress bar that fills from the leading edge to `fraction` (0...1).
private struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}
