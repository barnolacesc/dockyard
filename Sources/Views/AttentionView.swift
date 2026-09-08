// ABOUTME: Read-only inbox for Coding Agent activity across all workstreams.
// ABOUTME: Highlights unread attention items and deep-links back to their workstreams.

import SwiftUI

struct SidebarAttentionRow: View {
    let unreadCount: Int
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

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tabularNumbers()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignColor.statusWarning, in: Capsule())
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
            unreadCount > 0
                ? String(format: NSLocalizedString("%d unread", comment: "Unread agent activity count"), unreadCount)
                : ""
        )
    }
}

struct AttentionView: View {
    let projects: [Project]
    let onSelectWorkstream: (UUID) -> Void

    @EnvironmentObject private var activityStore: AgentActivityStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var unreadEvents: [AgentActivityEvent] {
        activityStore.events.filter(\.isUnread)
    }

    private var readEvents: [AgentActivityEvent] {
        activityStore.events.filter { !$0.isUnread }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header

                if activityStore.events.isEmpty {
                    emptyState
                } else {
                    if !unreadEvents.isEmpty {
                        activitySection(title: "Needs attention", events: unreadEvents)
                    }
                    if !readEvents.isEmpty {
                        activitySection(title: "Recent activity", events: readEvents)
                    }
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
                    if activityStore.unreadCount > 0 {
                        Text("\(activityStore.unreadCount)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DesignColor.statusWarning, in: Capsule())
                    }
                }
                Text("See which Coding Agents need you and what changed while you were elsewhere.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if activityStore.unreadCount > 0 {
                Button("Mark all as read") {
                    if reduceMotion {
                        activityStore.markAllRead()
                    } else {
                        withAnimation(DesignMotion.interaction) {
                            activityStore.markAllRead()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .pressable()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DesignColor.statusSuccess)
            Text("You're all caught up")
                .font(.headline)
            Text("Coding Agent activity will appear here as workstreams start, finish, or wait for your input.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private func activitySection(title: LocalizedStringKey, events: [AgentActivityEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(events.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 1) {
                ForEach(events) { event in
                    activityRow(event)
                    if event.id != events.last?.id {
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

    private func activityRow(_ event: AgentActivityEvent) -> some View {
        let context = workstreamContext(for: event.workstreamID)
        return Button {
            activityStore.markRead(event.id)
            if context != nil {
                onSelectWorkstream(event.workstreamID)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: event.kind.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint(for: event.kind))
                    .frame(width: 40, height: 40)
                    .background(tint(for: event.kind).opacity(0.11), in: RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(event.kind.titleKey))
                        .font(.body.weight(event.isUnread ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(context.map { "\($0.projectName) · \($0.workstreamName)" } ?? NSLocalizedString("Unknown workstream", comment: "Attention event with a removed workstream"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(event.occurredAt, style: .relative)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

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

    private func tint(for kind: AgentActivityKind) -> Color {
        switch kind {
        case .started: DesignColor.statusSuccess
        case .waiting: DesignColor.statusWarning
        case .completed: DesignColor.statusInfo
        case .inactive: .secondary
        }
    }
}
