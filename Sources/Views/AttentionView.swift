// ABOUTME: Read-only inbox for Coding Agent activity across all workstreams.
// ABOUTME: Highlights unread attention items and deep-links back to their workstreams.

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

                if attentionCount > 0 {
                    UnreadCountBadge(count: attentionCount)
                }
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
        .accessibilityValue(
            attentionCount > 0
                ? String(format: NSLocalizedString("%d need attention", comment: "Current agents waiting for attention count"), attentionCount)
                : ""
        )
    }
}

private struct AttentionWorkstream: Identifiable {
    let id: UUID
    let state: AgentState
}

struct AttentionView: View {
    let projects: [Project]
    let onSelectWorkstream: (UUID) -> Void

    @EnvironmentObject private var agentStateStore: AgentStateStore

    private var currentWorkstreams: [AttentionWorkstream] {
        projects
            .flatMap(\.workstreams)
            .compactMap { workstream in
                guard let state = agentStateStore.agentState(for: workstream.id),
                      state == .working || state == .waiting
                else { return nil }
                return AttentionWorkstream(id: workstream.id, state: state)
            }
            .sorted { lhs, rhs in
                if lhs.state != rhs.state {
                    return lhs.state == .waiting
                }
                return workstreamContext(for: lhs.id)?.workstreamName ?? "" < workstreamContext(for: rhs.id)?.workstreamName ?? ""
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header

                if currentWorkstreams.isEmpty {
                    emptyState
                } else {
                    workspaceSection
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
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
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Attention")
                        .font(.title2.weight(.semibold))
                    if attentionCount > 0 {
                        UnreadCountBadge(count: attentionCount)
                    }
                }
                Text("See the Coding Agents that are currently working or waiting for you.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

        }
    }

    private var attentionCount: Int {
        currentWorkstreams.filter { $0.state == .waiting }.count
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DesignColor.statusSuccess)
            Text("No active Coding Agents")
                .font(.headline)
            Text("Workstreams appear here while their Coding Agent is working or waiting for your input.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Current workspaces")
                    .font(.headline)
                Spacer()
                Text("\(currentWorkstreams.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 1) {
                ForEach(currentWorkstreams) { workstream in
                    workspaceRow(workstream)
                    if workstream.id != currentWorkstreams.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignRadius.xl, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07))
            }
        }
    }

    private func workspaceRow(_ workstream: AttentionWorkstream) -> some View {
        let context = workstreamContext(for: workstream.id)
        return Button {
            if context != nil {
                onSelectWorkstream(workstream.id)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage(for: workstream.state))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint(for: workstream.state))
                    .frame(width: 40, height: 40)
                    .background(tint(for: workstream.state).opacity(0.11), in: RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleKey(for: workstream.state))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(context.map { "\($0.projectName) · \($0.workstreamName)" } ?? NSLocalizedString("Unknown workstream", comment: "Attention event with a removed workstream"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(context == nil)
        .hoverHighlight(radius: DesignRadius.lg)
        .accessibilityHint(context == nil ? "" : NSLocalizedString("Open workstream", comment: "Attention row accessibility hint"))
    }

    private func workstreamContext(for id: UUID) -> (projectName: String, workstreamName: String)? {
        for project in projects {
            if let workstream = project.workstreams.first(where: { $0.id == id }) {
                return (project.name, workstream.name)
            }
        }
        return nil
    }

    private func systemImage(for state: AgentState) -> String {
        switch state {
        case .working: "bolt.fill"
        case .waiting: "questionmark.bubble.fill"
        case .idle: "pause.circle.fill"
        }
    }

    private func titleKey(for state: AgentState) -> LocalizedStringKey {
        switch state {
        case .working: "Agent is working"
        case .waiting: "Agent needs your attention"
        case .idle: "Agent became inactive"
        }
    }

    private func tint(for state: AgentState) -> Color {
        switch state {
        case .working: DesignColor.statusSuccess
        case .waiting: DesignColor.statusWarning
        case .idle: .secondary
        }
    }
}
