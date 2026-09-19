// ABOUTME: Container view for project detail area with tabs for Overview and Terminal.
// ABOUTME: Preserves the project terminal surface while allowing switching to the project overview.

import SwiftUI

enum ProjectTab: Hashable, CaseIterable {
    case overview
    case terminal
}

struct ProjectContainerView: View {
    @Binding var project: Project
    @Binding var activeTab: ProjectTab
    @Binding var isTerminalOpen: Bool
    let onSelectWorkstream: (UUID) -> Void
    let onRemoveWorkstream: (UUID) -> Void
    let onPurgeWorkstream: (UUID) -> Void
    let onProjectChanged: () -> Void

    @EnvironmentObject private var surfaceCache: TerminalSurfaceCache

    private var surfaceID: UUID {
        derivedUUID(from: project.id, salt: "project-root-terminal")
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()

            switch activeTab {
            case .overview:
                ProjectOverviewView(
                    project: $project,
                    onSelectWorkstream: onSelectWorkstream,
                    onRemoveWorkstream: onRemoveWorkstream,
                    onPurgeWorkstream: onPurgeWorkstream,
                    onProjectChanged: onProjectChanged
                )
            case .terminal:
                SingleTerminalView(
                    surfaceID: surfaceID,
                    workstreamID: project.id,
                    workingDirectory: project.directory
                )
            }
        }
        .onAppear {
            updateOcclusion()
        }
        .onDisappear {
            surfaceCache.updateOcclusion(visibleSurfaceIDs: [])
        }
        .onChange(of: activeTab) { _, _ in
            updateOcclusion()
        }
        .onChange(of: isTerminalOpen) { _, open in
            if !open && activeTab == .terminal {
                activeTab = .overview
            }
            updateOcclusion()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchByNumber)) { notification in
            guard let digit = notification.object as? Int else { return }
            if digit == 1 {
                activeTab = .overview
            } else if digit == 2 {
                isTerminalOpen = true
                activeTab = .terminal
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTerminal)) { _ in
            isTerminalOpen = true
            activeTab = .terminal
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTerminal)) { _ in
            if activeTab == .terminal {
                closeTerminal()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prevTab)) { _ in
            cycleTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextTab)) { _ in
            cycleTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalTabExited)) { notification in
            guard notification.object as? UUID == surfaceID else { return }
            closeTerminal()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ProjectTabButton(
                label: "Overview",
                icon: "info.circle",
                shortcut: "1",
                isActive: activeTab == .overview,
                onSelect: { activeTab = .overview },
                onClose: nil
            )

            if isTerminalOpen {
                ProjectTabButton(
                    label: "Terminal",
                    icon: "terminal",
                    shortcut: "2",
                    isActive: activeTab == .terminal,
                    onSelect: { activeTab = .terminal },
                    onClose: { closeTerminal() }
                )
            }

            Spacer()

            TabBarActionButton(
                icon: "terminal",
                shortcut: "⌘T",
                tooltip: "New Terminal (⌘T)"
            ) {
                isTerminalOpen = true
                activeTab = .terminal
            }
            .shortcutHint(ShortcutHint(command: "T"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(.bar)
    }

    private func closeTerminal() {
        isTerminalOpen = false
        activeTab = .overview
        surfaceCache.removeProjectRootSurface(for: project.id)
    }

    private func cycleTab() {
        guard isTerminalOpen else { return }
        activeTab = (activeTab == .overview) ? .terminal : .overview
    }

    private func updateOcclusion() {
        if isTerminalOpen, activeTab == .terminal {
            surfaceCache.updateOcclusion(visibleSurfaceIDs: [surfaceID])
        } else {
            surfaceCache.updateOcclusion(visibleSurfaceIDs: [])
        }
    }
}

private struct ProjectTabButton: View {
    let label: LocalizedStringKey
    let icon: String
    var shortcut: String? = nil
    let isActive: Bool
    let onSelect: () -> Void
    var onClose: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .offset(y: 0.5)
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                if let shortcut {
                    (Text(Image(systemName: "command")) + Text(shortcut))
                        .font(.system(size: 9))
                        .tabularNumbers()
                        .foregroundStyle(.tertiary)
                }
                if let onClose, isHovering || isActive {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(Circle())
                        .onTapGesture(perform: onClose)
                        .accessibilityLabel("Close tab")
                }
            }
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, DesignSpacing.xs)
            .frame(minHeight: 40)
            .background(isActive ? Color.accentColor.opacity(0.15) : (isHovering ? Color.primary.opacity(0.05) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous))
            .foregroundStyle(isActive ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .pressable()
        .onHover { isHovering = $0 }
    }
}
