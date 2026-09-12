// ABOUTME: Glanceable overview of current work across every Dockyard project.
// ABOUTME: Prioritizes workstreams that need input, then groups active, review, and ready work.

import SwiftUI

struct UnreadCountBadge: View {
    let count: Int
    var compact = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .rounded))
            .tabularNumbers()
            .foregroundStyle(DesignColor.badgeForeground)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .background(DesignColor.statusWarning, in: Capsule())
    }
}

struct SidebarAttentionRow: View {
    let attentionCount: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "bell.fill" : "bell")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                Text("Attention")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer()
                if attentionCount > 0 { UnreadCountBadge(count: attentionCount) }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressable()
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : DesignMotion.interaction, value: isHovering)
        .accessibilityLabel("Attention")
        .accessibilityValue(attentionCount > 0 ? String(format: NSLocalizedString("%d need attention", comment: "Current agents waiting for attention count"), attentionCount) : "")
    }
}

private enum AttentionCategory: Int, CaseIterable, Identifiable {
    case needsYou, inProgress, review, ready
    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .needsYou: "Needs you"
        case .inProgress: "In progress"
        case .review: "In review"
        case .ready: "Ideas & ready"
        }
    }

    var summaryTitle: LocalizedStringKey {
        switch self {
        case .needsYou: "Waiting"
        case .inProgress: "Working"
        case .review: "Review"
        case .ready: "Ready"
        }
    }

    var systemImage: String {
        switch self {
        case .needsYou: "exclamationmark.bubble.fill"
        case .inProgress: "bolt.fill"
        case .review: "arrow.triangle.pull"
        case .ready: "lightbulb.fill"
        }
    }

    var tint: Color {
        switch self {
        case .needsYou: DesignColor.statusWarning
        case .inProgress: DesignColor.statusSuccess
        case .review: DesignColor.statusMerged
        case .ready: DesignColor.statusInfo
        }
    }

    var sectionDescription: LocalizedStringKey {
        switch self {
        case .needsYou: "Waiting for your input or approval."
        case .inProgress: "Coding Agents working right now."
        case .review: "Workstreams ready to review."
        case .ready: "Ideas and workstreams ready to continue."
        }
    }
}

private struct AttentionWorkstream: Identifiable {
    let id: UUID
    let projectName: String
    let workstreamName: String
    let lastAccessedAt: Date
    let category: AttentionCategory
}

struct AttentionView: View {
    let projects: [Project]
    let onSelectWorkstream: (UUID) -> Void
    @EnvironmentObject private var agentStateStore: AgentStateStore

    private var currentWorkstreams: [AttentionWorkstream] {
        projects.flatMap { project in
            project.workstreams.compactMap { workstream in
                guard workstream.stage != .done else { return nil }
                return AttentionWorkstream(
                    id: workstream.id,
                    projectName: project.name,
                    workstreamName: workstream.name,
                    lastAccessedAt: workstream.lastAccessedAt,
                    category: category(for: workstream)
                )
            }
        }
    }

    private var attentionCount: Int { workstreams(in: .needsYou).count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                if currentWorkstreams.isEmpty {
                    emptyState
                } else {
                    summary
                    ForEach(AttentionCategory.allCases) { category in
                        let rows = workstreams(in: category)
                        if !rows.isEmpty { workspaceSection(category, workstreams: rows) }
                    }
                }
            }
            .frame(maxWidth: 840, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "rectangle.3.group.bubble.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Dockyard overview").font(.title2.weight(.semibold))
                    if attentionCount > 0 { UnreadCountBadge(count: attentionCount) }
                }
                Text("See what needs you, what is moving, and what is ready to pick up next.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
            ForEach(AttentionCategory.allCases) { category in
                HStack(spacing: 10) {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(category.tint)
                        .frame(width: 30, height: 30)
                        .background(category.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(workstreams(in: category).count)").font(.headline.monospacedDigit())
                        Text(category.summaryTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous).strokeBorder(category.tint.opacity(0.12)) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DesignColor.statusSuccess)
            Text("Nothing on deck").font(.headline)
            Text("Create a workstream and it will appear here as part of your Dockyard overview.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private func workspaceSection(_ category: AttentionCategory, workstreams: [AttentionWorkstream]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.title).font(.headline)
                Text(category.sectionDescription).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(workstreams.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            VStack(spacing: 1) {
                ForEach(workstreams) { workstream in
                    workspaceRow(workstream)
                    if workstream.id != workstreams.last?.id { Divider().padding(.leading, 62) }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.xl, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: DesignRadius.xl, style: .continuous).strokeBorder(.primary.opacity(0.07)) }
        }
    }

    private func workspaceRow(_ workstream: AttentionWorkstream) -> some View {
        Button { onSelectWorkstream(workstream.id) } label: {
            HStack(spacing: 14) {
                Image(systemName: workstream.category.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(workstream.category.tint)
                    .frame(width: 40, height: 40)
                    .background(workstream.category.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(workstream.workstreamName).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(workstream.projectName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Text(workstream.lastAccessedAt, style: .relative)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressable()
        .hoverHighlight(radius: DesignRadius.lg)
        .accessibilityHint(NSLocalizedString("Open workstream", comment: "Attention row accessibility hint"))
    }

    private func workstreams(in category: AttentionCategory) -> [AttentionWorkstream] {
        currentWorkstreams.filter { $0.category == category }.sorted {
            if $0.lastAccessedAt != $1.lastAccessedAt { return $0.lastAccessedAt > $1.lastAccessedAt }
            return $0.workstreamName.localizedCaseInsensitiveCompare($1.workstreamName) == .orderedAscending
        }
    }

    private func category(for workstream: Workstream) -> AttentionCategory {
        switch agentStateStore.agentState(for: workstream.id) {
        case .waiting: .needsYou
        case .working: .inProgress
        case .idle, nil: workstream.stage == .review ? .review : .ready
        }
    }
}
