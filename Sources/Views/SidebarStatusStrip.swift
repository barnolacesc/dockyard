// ABOUTME: Status strip at the bottom of the sidebar: provider usage meters with current and
// ABOUTME: weekly windows plus a thin project/workstream/PR count line.

import SwiftUI

struct SidebarStatusStrip: View {
    let projectCount: Int
    let workstreamCount: Int
    let openPRCount: Int
    var waitingCount: Int = 0
    var selectedUsageProvider: UsageMeterProvider = .claude
    var availableUsageProviders: [UsageMeterProvider] = [.claude]
    var onPreviousUsageProvider: () -> Void = {}
    var onNextUsageProvider: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarUsageMeter(
                style: .expanded,
                selectedProvider: selectedUsageProvider,
                availableProviders: availableUsageProviders,
                onPreviousProvider: onPreviousUsageProvider,
                onNextProvider: onNextUsageProvider
            )
            countsLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Counts

    private var countsLine: some View {
        HStack(spacing: 12) {
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
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
    }

    private func countItem(systemImage: String, count: Int) -> some View {
        HStack(spacing: 3) {
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

struct SidebarUsageMeter: View {
    enum Style {
        case expanded
        case compact
    }

    let style: Style
    var selectedProvider: UsageMeterProvider = .claude
    var availableProviders: [UsageMeterProvider] = [.claude]
    var onPreviousProvider: () -> Void = {}
    var onNextProvider: () -> Void = {}

    @EnvironmentObject private var usageStore: ClaudeUsageStore
    @EnvironmentObject private var codexUsageStore: CodexUsageStore
    @AppStorage("dockyard.claudePlanTier") private var planTierRaw = ClaudePlanTier.none.rawValue

    private var planTier: ClaudePlanTier { ClaudePlanTier(rawValue: planTierRaw) ?? .none }

    /// Lime green for the weekly bar, to contrast with the orange 5-hour bar.
    private static let weeklyTint = Color(red: 0.62, green: 0.80, blue: 0.30)

    var body: some View {
        switch usageMeterDisplayState(selectedHasData: hasAnyData, providerCount: availableProviders.count) {
        case .hidden:
            EmptyView()
        case .placeholder:
            // The selected provider has no data yet but others exist. Keep the switcher visible
            // (expanded only — the compact rail has no switcher) so the user can cycle back.
            if style == .expanded {
                meterShell {
                    VStack(alignment: .leading, spacing: 8) {
                        expandedHeader
                        placeholderRow
                    }
                }
            }
        case .data:
            TimelineView(.periodic(from: .now, by: 30)) { context in
                meterShell {
                    VStack(alignment: style == .compact ? .center : .leading, spacing: style == .compact ? 6 : 8) {
                        if style == .expanded {
                            expandedHeader
                        }

                        if let currentRow = currentRow(now: context.date) {
                            currentRow
                        }
                        if let weeklyRow {
                            weeklyRow
                        }
                    }
                }
            }
        }
    }

    /// Common interaction wrapper for the meter: tap to refresh, pointer cursor on hover, tooltip.
    private func meterShell(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture { refreshSelectedProvider() }
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help(usageTooltip)
    }

    @ViewBuilder
    private var placeholderRow: some View {
        HStack(spacing: 6) {
            if isRefreshingSelectedProvider {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Fetching usage…")
            } else {
                Text("No usage data — tap to refresh")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }

    private var isRefreshingSelectedProvider: Bool {
        switch selectedProvider {
        case .claude:
            return usageStore.isRefreshing
        case .codex:
            return codexUsageStore.isRefreshing
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 5) {
            Image(systemName: "gauge.with.needle.fill")
                .foregroundStyle(Color.accentColor)
            Text("Usage")
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 4)
            if availableProviders.count > 1 {
                usageProviderButton(systemImage: "chevron.left", label: NSLocalizedString("Previous usage meter", comment: "Usage meter previous provider button")) {
                    onPreviousProvider()
                }
            }
            Text(selectedProvider.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 78, alignment: .trailing)
            if availableProviders.count > 1 {
                usageProviderButton(systemImage: "chevron.right", label: NSLocalizedString("Next usage meter", comment: "Usage meter next provider button")) {
                    onNextProvider()
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    private func usageProviderButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }

    private var hasAnyData: Bool {
        switch selectedProvider {
        case .claude:
            return usageStore.hasAnyData
        case .codex:
            return codexUsageStore.hasAnyData
        }
    }

    /// Current (5-hour) window. Prefers the real `/usage` figure, falls back to the estimate.
    private func currentRow(now: Date) -> UsageMeterRow? {
        switch selectedProvider {
        case .claude:
            return claudeCurrentRow(now: now)
        case .codex:
            return codexCurrentRow
        }
    }

    private func claudeCurrentRow(now: Date) -> UsageMeterRow {
        let label = NSLocalizedString("Current", comment: "Claude 5-hour usage window")
        if let session = usageStore.report?.session {
            return UsageMeterRow(
                headline: "\(session.percentUsed)%",
                label: label,
                tint: .orange,
                fraction: Double(session.percentUsed) / 100,
                subtitle: session.resetText.map(Self.resetsString),
                style: style
            )
        }
        let window = usageStore.snapshot.fiveHour
        return UsageMeterRow(
            headline: estimateHeadline(tokens: window.tokens, budget: planTier.fiveHourTokenBudget),
            label: label,
            tint: .orange,
            fraction: fraction(tokens: window.tokens, budget: planTier.fiveHourTokenBudget),
            subtitle: estimateResetSubtitle(window.resetAt, now: now),
            style: style
        )
    }

    /// Weekly (7-day) window. Prefers the real `/usage` figure, falls back to the estimate.
    private var weeklyRow: UsageMeterRow? {
        switch selectedProvider {
        case .claude:
            return claudeWeeklyRow
        case .codex:
            return codexWeeklyRow
        }
    }

    private var claudeWeeklyRow: UsageMeterRow {
        let label = NSLocalizedString("Weekly", comment: "Claude 7-day usage window")
        if let week = usageStore.report?.week {
            return UsageMeterRow(
                headline: "\(week.percentUsed)%",
                label: label,
                tint: Self.weeklyTint,
                fraction: Double(week.percentUsed) / 100,
                subtitle: week.resetText.map(Self.resetsString),
                style: style
            )
        }
        let window = usageStore.snapshot.sevenDay
        return UsageMeterRow(
            headline: estimateHeadline(tokens: window.tokens, budget: planTier.weeklyTokenBudget),
            label: label,
            tint: Self.weeklyTint,
            fraction: fraction(tokens: window.tokens, budget: planTier.weeklyTokenBudget),
            subtitle: NSLocalizedString("rolling 7 days", comment: "Claude weekly usage window"),
            style: style
        )
    }

    private var codexCurrentRow: UsageMeterRow? {
        codexRow(
            window: codexUsageStore.report?.fiveHour,
            label: NSLocalizedString("Current", comment: "Codex 5-hour usage window"),
            tint: .orange
        )
    }

    private var codexWeeklyRow: UsageMeterRow? {
        codexRow(
            window: codexUsageStore.report?.week,
            label: NSLocalizedString("Weekly", comment: "Codex weekly usage window"),
            tint: Self.weeklyTint
        )
    }

    private func codexRow(window: CodexUsageReport.Window?, label: String, tint: Color) -> UsageMeterRow? {
        guard let window else { return nil }
        let percentUsed = CodexUsageProbe.percentUsed(fromPercentLeft: window.percentLeft)
        return UsageMeterRow(
            headline: "\(percentUsed)%",
            label: label,
            tint: tint,
            fraction: Double(percentUsed) / 100,
            subtitle: window.resetText.map(Self.resetsString),
            style: style
        )
    }

    private func fraction(tokens: Int, budget: Int?) -> Double {
        guard let budget, budget > 0 else { return 0 }
        return min(1, Double(tokens) / Double(budget))
    }

    private func estimateHeadline(tokens: Int, budget: Int?) -> String {
        guard let budget, budget > 0 else { return SidebarStatusStrip.formatTokens(tokens) }
        return "\(Int((min(1, Double(tokens) / Double(budget)) * 100).rounded()))%"
    }

    private func estimateResetSubtitle(_ resetAt: Date?, now: Date) -> String? {
        guard let resetAt, resetAt > now else { return nil }
        return String(
            format: NSLocalizedString("resets in %@", comment: "usage window reset countdown"),
            SidebarStatusStrip.formatDuration(resetAt.timeIntervalSince(now))
        )
    }

    private static func resetsString(_ text: String) -> String {
        String(format: NSLocalizedString("resets %@", comment: "usage window reset time"), text)
    }

    private func refreshSelectedProvider() {
        switch selectedProvider {
        case .claude:
            usageStore.refresh(force: true)
        case .codex:
            codexUsageStore.refresh(force: true)
        }
    }

    private var usageTooltip: String {
        switch selectedProvider {
        case .claude:
            return claudeUsageTooltip
        case .codex:
            return NSLocalizedString("Real usage from Codex /status. Click to refresh.", comment: "")
        }
    }

    private var claudeUsageTooltip: String {
        if usageStore.report != nil {
            return NSLocalizedString("Real usage from Claude Code's /usage. Click to refresh.", comment: "")
        }
        let snap = usageStore.snapshot
        let five = String(format: NSLocalizedString("Last 5 hours: %@ tokens", comment: ""), SidebarStatusStrip.formatTokens(snap.fiveHour.tokens))
        let week = String(format: NSLocalizedString("Last 7 days: %@ tokens", comment: ""), SidebarStatusStrip.formatTokens(snap.sevenDay.tokens))
        let note = NSLocalizedString("Estimated from local Claude Code transcripts (CLI only, not your full account). Percentages are approximate.", comment: "")
        return "\(five)\n\(week)\n\(note)"
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
    let style: SidebarUsageMeter.Style

    /// Shift toward red as the window approaches its limit.
    private var barTint: Color {
        fraction >= 0.9 ? .red : tint
    }

    var body: some View {
        switch style {
        case .expanded:
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
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        case .compact:
            VStack(alignment: .center, spacing: 3) {
                Text(headline)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(barTint)
                    .lineLimit(1)
                UsageBar(fraction: fraction, tint: barTint)
                    .frame(width: 42)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(headline)
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
