// ABOUTME: Compact collapsed sidebar rail for project/workstream navigation.
// ABOUTME: Shows projects as numbers, selected project workstreams as letters, and compact status.

import SwiftUI

struct SidebarRailStatus: Equatable {
    var isWaiting: Bool = false
    var dirtyCount: Int = 0
}

func sidebarRailProjectLabel(at index: Int) -> String {
    "\(index + 1)"
}

func sidebarRailWorkstreamLabel(at index: Int) -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
    guard index >= 0 else { return "" }
    if index < alphabet.count {
        return String(alphabet[index])
    }
    let first = alphabet[(index / alphabet.count) - 1]
    let second = alphabet[index % alphabet.count]
    return "\(first)\(second)"
}

func sidebarRailSortedProjects(_ projects: [Project]) -> [Project] {
    projects.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
}

func sidebarRailSortedWorkstreams(_ workstreams: [Workstream]) -> [Workstream] {
    workstreams.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
}

func sidebarRailProjectStatus(
    for project: Project,
    waitingWorkstreamIDs: Set<UUID>,
    dirtyCountsByWorkstreamID: [UUID: Int]
) -> SidebarRailStatus {
    SidebarRailStatus(
        isWaiting: project.workstreams.contains { waitingWorkstreamIDs.contains($0.id) },
        dirtyCount: project.workstreams.reduce(0) { $0 + max(0, dirtyCountsByWorkstreamID[$1.id] ?? 0) }
    )
}

func sidebarRailWorkstreamStatus(
    for workstream: Workstream,
    waitingWorkstreamIDs: Set<UUID>,
    dirtyCountsByWorkstreamID: [UUID: Int]
) -> SidebarRailStatus {
    SidebarRailStatus(
        isWaiting: waitingWorkstreamIDs.contains(workstream.id),
        dirtyCount: max(0, dirtyCountsByWorkstreamID[workstream.id] ?? 0)
    )
}

struct SidebarRail: View {
    @Binding var projects: [Project]
    @Binding var selection: SidebarSelection?
    @ObservedObject var appUpdater: AppUpdater
    let onExpand: () -> Void
    let onAddExistingDirectory: () -> Void
    let onCreateNewProject: () -> Void

    @EnvironmentObject private var appEnv: AppEnvironment
    @EnvironmentObject private var agentStateStore: AgentStateStore
    @EnvironmentObject private var activityTracker: WorkstreamActivityTracker
    @EnvironmentObject private var usageStore: ClaudeUsageStore

    private var sortedProjects: [Project] {
        sidebarRailSortedProjects(projects)
    }

    private var selectedProjectID: UUID? {
        switch selection {
        case let .project(id):
            return id
        case let .workstream(workstreamID):
            return projects.first { $0.workstreams.contains { $0.id == workstreamID } }?.id
        case .settings, .help, nil:
            return nil
        }
    }

    private var selectedWorkstreamID: UUID? {
        selection?.workstreamID
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onExpand) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("Expand sidebar", comment: "Collapsed sidebar expand button tooltip"))
            .accessibilityLabel("Expand sidebar")
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(Array(sortedProjects.enumerated()), id: \.element.id) { index, project in
                        let isSelectedProject = project.id == selectedProjectID
                        let projectStatus = isSelectedProject ? SidebarRailStatus() : status(for: project)

                        RailProjectTile(
                            label: sidebarRailProjectLabel(at: index),
                            tooltip: projectDirectoryName(project),
                            isSelected: isSelectedProject,
                            status: projectStatus,
                            onSelect: { selection = .project(project.id) }
                        )

                        if isSelectedProject {
                            let sortedWorkstreams = sidebarRailSortedWorkstreams(project.workstreams)
                            ForEach(Array(sortedWorkstreams.enumerated()), id: \.element.id) { workstreamIndex, workstream in
                                RailWorkstreamTile(
                                    label: sidebarRailWorkstreamLabel(at: workstreamIndex),
                                    tooltip: workstreamTooltip(workstream),
                                    isSelected: workstream.id == selectedWorkstreamID,
                                    status: status(for: workstream),
                                    onSelect: { selection = .workstream(workstream.id) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 8)

            SidebarUsageMeter(style: .compact)
                .padding(.horizontal, 8)
                .padding(.bottom, usageStore.hasAnyData ? 10 : 0)

            VStack(spacing: 8) {
                updateButton

                Menu {
                    Button("Add Existing Directory…", action: onAddExistingDirectory)
                    Button("Create New Project…", action: onCreateNewProject)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 30)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(NSLocalizedString("Add project", comment: "Collapsed sidebar add project button tooltip"))
                .accessibilityLabel("Add project")

                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 36, height: 30)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("Settings", comment: "Collapsed sidebar settings button tooltip"))
                .accessibilityLabel("Settings")
            }
            .padding(.bottom, 8)
        }
        .frame(width: 60)
    }

    @ViewBuilder
    private var updateButton: some View {
        if appUpdater.isChecking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 36, height: 30)
        } else if appUpdater.commitsAhead > 0 {
            Button(action: { appUpdater.applyUpdate() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 30)
                    Text("\(appUpdater.commitsAhead)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange, in: Capsule())
                        .offset(x: 4, y: -2)
                }
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("Pull latest changes from main and rebuild", comment: "Collapsed sidebar update button tooltip"))
            .accessibilityLabel("Update")
            .accessibilityValue("\(appUpdater.commitsAhead)")
        } else {
            Button(action: { appUpdater.checkForUpdates() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(NSLocalizedString("Check for updates", comment: "Collapsed sidebar update check button tooltip"))
            .accessibilityLabel("Update")
        }
    }

    private func status(for project: Project) -> SidebarRailStatus {
        sidebarRailProjectStatus(
            for: project,
            waitingWorkstreamIDs: waitingWorkstreamIDs(in: project.workstreams),
            dirtyCountsByWorkstreamID: dirtyCountsByWorkstreamID(in: project.workstreams)
        )
    }

    private func status(for workstream: Workstream) -> SidebarRailStatus {
        sidebarRailWorkstreamStatus(
            for: workstream,
            waitingWorkstreamIDs: agentStateStore.agentState(for: workstream.id) == .waiting ? [workstream.id] : [],
            dirtyCountsByWorkstreamID: [workstream.id: dirtyCount(for: workstream)]
        )
    }

    private func waitingWorkstreamIDs(in workstreams: [Workstream]) -> Set<UUID> {
        Set(workstreams.filter { agentStateStore.agentState(for: $0.id) == .waiting }.map(\.id))
    }

    private func dirtyCountsByWorkstreamID(in workstreams: [Workstream]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: workstreams.map { ($0.id, dirtyCount(for: $0)) })
    }

    private func dirtyCount(for workstream: Workstream) -> Int {
        guard let path = workstream.worktreePath else { return 0 }
        return appEnv.worktreeState(for: path).uncommittedCount
    }

    private func projectDirectoryName(_ project: Project) -> String {
        let name = URL(fileURLWithPath: project.directory).lastPathComponent
        return name.isEmpty ? project.name : name
    }

    private func workstreamTooltip(_ workstream: Workstream) -> String {
        if let branch = appEnv.branchName(for: workstream.worktreePath) {
            return branch
        }
        return "dy/\(workstream.name)"
    }
}

private struct RailProjectTile: View {
    let label: String
    let tooltip: String
    let isSelected: Bool
    let status: SidebarRailStatus
    let onSelect: () -> Void

    var body: some View {
        RailTile(
            label: label,
            tooltip: tooltip,
            isSelected: isSelected,
            isWorkstream: false,
            status: status,
            onSelect: onSelect
        )
    }
}

private struct RailWorkstreamTile: View {
    let label: String
    let tooltip: String
    let isSelected: Bool
    let status: SidebarRailStatus
    let onSelect: () -> Void

    var body: some View {
        RailTile(
            label: label,
            tooltip: tooltip,
            isSelected: isSelected,
            isWorkstream: true,
            status: status,
            onSelect: onSelect
        )
    }
}

private struct RailTile: View {
    let label: String
    let tooltip: String
    let isSelected: Bool
    let isWorkstream: Bool
    let status: SidebarRailStatus
    let onSelect: () -> Void

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var foreground: Color {
        if isWorkstream, isSelected { return .orange }
        return isSelected ? .primary : .secondary
    }

    private var background: Color {
        if isWorkstream, isSelected { return Color.orange.opacity(0.18) }
        return isSelected ? Color.primary.opacity(0.08) : Color.clear
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                Text(label)
                    .font(.system(size: isWorkstream ? 13 : 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(foreground)
                    .frame(width: 36, height: 32)
                    .background(background, in: tileShape)
                    .overlay {
                        if isSelected {
                            tileShape.stroke(isWorkstream ? Color.orange : Color.accentColor, lineWidth: 1.5)
                        }
                    }

                if status.isWaiting {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: -2)
                }

                if status.dirtyCount > 0 {
                    Text("\(status.dirtyCount)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(Color.orange, in: Capsule())
                        .offset(x: 4, y: 21)
                }
            }
            .frame(width: 40, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
    }
}
