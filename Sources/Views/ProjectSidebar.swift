// ABOUTME: SwiftUI sidebar showing projects as a collapsible tree with workstreams.
// ABOUTME: Supports adding projects via picker/drag-drop and workstreams inline.

import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "dockyard", category: "sidebar")

func expandedProjectIDs(afterSelecting selection: SidebarSelection?, current: Set<UUID>, projectIDByWorkstreamID: [UUID: UUID]) -> Set<UUID> {
    guard let selection else { return current }
    var expanded = current
    switch selection {
    case let .project(projectID):
        expanded.insert(projectID)
    case let .workstream(workstreamID):
        if let projectID = projectIDByWorkstreamID[workstreamID] {
            expanded.insert(projectID)
        }
    case .attention, .settings, .help:
        break
    }
    return expanded
}

func moveProjects(_ projects: inout [Project], fromOffsets source: IndexSet, toOffset destination: Int) {
    projects.move(fromOffsets: source, toOffset: destination)
}

func moveWorkstreams(in projects: inout [Project], projectID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
    guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
    projects[projectIndex].workstreams.move(fromOffsets: source, toOffset: destination)
}

extension Notification.Name {
    static let addProject = Notification.Name("dockyard.addProject")
    static let addNew = Notification.Name("dockyard.addNew")
}

struct WorkstreamStagePillStyle: Equatable {
    enum Appearance: Equatable {
        case filled
        case outline
        case bare
    }

    let appearance: Appearance
    let iconSystemName: String?
    let titleKey: String
    let prNumber: Int?
    let showsManualMark: Bool
    var tintColor: Color? = nil
}

extension GitHubPR {
    func stagePill(isManuallySet: Bool, includeNumber: Bool = true) -> WorkstreamStagePillStyle? {
        let numberToDisplay = includeNumber ? number : nil

        if isDraft {
            return WorkstreamStagePillStyle(
                appearance: .outline,
                iconSystemName: "doc.text",
                titleKey: "Draft",
                prNumber: numberToDisplay,
                showsManualMark: isManuallySet,
                tintColor: .secondary
            )
        }

        switch codeRabbitStatus {
        case .hasFindings(let count):
            let title = count != nil ? "\(count!)" : "Findings"
            return WorkstreamStagePillStyle(
                appearance: .filled,
                iconSystemName: "sparkles",
                titleKey: title,
                prNumber: numberToDisplay,
                showsManualMark: isManuallySet,
                tintColor: DesignColor.statusWarning
            )
        case .reviewing:
            return WorkstreamStagePillStyle(
                appearance: .filled,
                iconSystemName: "clock",
                titleKey: "Reviewing",
                prNumber: numberToDisplay,
                showsManualMark: isManuallySet,
                tintColor: DesignColor.statusInfo
            )
        case .clean, .notConfigured:
            break
        }

        switch reviewStatus {
        case .changesRequested:
            return WorkstreamStagePillStyle(
                appearance: .filled,
                iconSystemName: "exclamationmark.bubble.fill",
                titleKey: "Changes",
                prNumber: numberToDisplay,
                showsManualMark: isManuallySet,
                tintColor: DesignColor.statusError
            )
        case .approved:
            return WorkstreamStagePillStyle(
                appearance: .filled,
                iconSystemName: "checkmark.seal.fill",
                titleKey: "Approved",
                prNumber: numberToDisplay,
                showsManualMark: isManuallySet,
                tintColor: DesignColor.statusSuccess
            )
        case .awaitingReview, .none:
            return WorkstreamStagePillStyle(
                appearance: .filled,
                iconSystemName: "arrow.triangle.pull",
                titleKey: "Review",
                prNumber: numberToDisplay,
                showsManualMark: isManuallySet,
                tintColor: DesignColor.statusMerged
            )
        case .draft:
            return WorkstreamStagePillStyle(
                appearance: .outline,
                iconSystemName: "doc.text",
                titleKey: "Draft",
                prNumber: numberToDisplay,
                showsManualMark: isManuallySet,
                tintColor: .secondary
            )
        }
    }
}

struct WorkstreamStageStyle: Equatable {
    let displayStage: WorkstreamDisplayStage
    let isManuallySet: Bool
    let prNumber: Int?
    var pullRequest: GitHubPR? = nil

    var recedesRow: Bool {
        displayStage == .done
    }

    var stagePill: WorkstreamStagePillStyle? {
        switch displayStage {
        case .normal:
            guard isManuallySet else { return nil }
            return WorkstreamStagePillStyle(
                appearance: .bare,
                iconSystemName: nil,
                titleKey: "Working",
                prNumber: nil,
                showsManualMark: true
            )
        case .review:
            if let pullRequest {
                return pullRequest.stagePill(isManuallySet: isManuallySet)
            }
            return WorkstreamStagePillStyle(
                appearance: .filled,
                iconSystemName: "arrow.triangle.pull",
                titleKey: "Review",
                prNumber: prNumber,
                showsManualMark: isManuallySet
            )
        case .done:
            return WorkstreamStagePillStyle(
                appearance: .outline,
                iconSystemName: "checkmark",
                titleKey: isManuallySet ? "Done" : "Merged",
                prNumber: prNumber,
                showsManualMark: isManuallySet
            )
        }
    }
}

struct ProjectSidebar: View {
    @Binding var projects: [Project]
    @Binding var selection: SidebarSelection?
    let onProjectsChanged: () -> Void
    @ObservedObject var appUpdater: AppUpdater
    var onOpenProjectTerminal: (UUID) -> Void = { _ in }
    var selectedUsageProvider: UsageMeterProvider = .claude
    var availableUsageProviders: [UsageMeterProvider] = [.claude]
    var onPreviousUsageProvider: () -> Void = {}
    var onNextUsageProvider: () -> Void = {}

    @State private var showingNewProjectName = false
    @State private var showingNewWorkstream = false
    @State private var newWorkstreamProjectID: UUID?
    @State private var configuredWorkstreamName = ""
    @State private var newWorkstreamCodingCLI = ""
    @State private var newWorkstreamBypassPermissions = false
    @State private var newWorkstreamIssue = ""
    @State private var newWorkstreamIssuePreview: GitHubIssueTaskPreview?
    @State private var newWorkstreamIssueError = ""
    @State private var isLoadingWorkstreamIssue = false
    @State private var newWorkstreamOpenIssues: [GitHubIssueTaskPreview] = []
    @State private var isLoadingOpenIssues = false
    @State private var openIssuesError = ""
    @State private var issueLookupToken = 0
    @State private var newProjectName = ""
    @State private var newProjectError = ""
    @State private var isDropTargeted = false
    @State private var projectToDelete: UUID?
    @State private var workstreamToRename: UUID?
    @State private var newWorkstreamName = ""
    @State private var workstreamToRemove: UUID?
    @State private var workstreamToPurge: UUID?
    @State private var purgeWarningMessage: String?
    @State private var expandedProjects: Set<UUID> = SidebarState.loadExpanded()
    @State private var cachedSortedIDs: [UUID] = []
    @State private var cachedSortedWorkstreamIDs: [UUID: [UUID]] = [:]
    @State private var cachedProjectIndex: [UUID: Int] = [:]
    @State private var cachedWorkstreamIndex: [UUID: (Int, Int)] = [:]
    @State private var showWorktreeError = false
    @State private var showNotGitRepoError = false
    @AppStorage("dockyard.showOpenPRs") private var showOpenPRs: Bool = true
    @AppStorage(SidebarMode.storageKey) private var sidebarModeRaw = SidebarMode.expanded.rawValue
    @AppStorage(SidebarMode.lastVisibleStorageKey) private var lastVisibleSidebarModeRaw = SidebarMode.expanded.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentVersionLooksLikeRelease: Bool {
        AppConstants.version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil
    }

    private var sidebarMode: SidebarMode {
        SidebarMode(rawValue: sidebarModeRaw) ?? .expanded
    }

    private func setVisibleSidebarMode(_ mode: SidebarMode) {
        guard mode.isVisible else { return }
        lastVisibleSidebarModeRaw = mode.rawValue
        sidebarModeRaw = mode.rawValue
    }

    private func recomputeSortedIDs() -> [UUID] {
        projects.map(\.id)
    }

    private func rebuildIndices() {
        cachedProjectIndex = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($1.id, $0) })
        var wsIndex: [UUID: (Int, Int)] = [:]
        var sortedWS: [UUID: [UUID]] = [:]
        for (pi, project) in projects.enumerated() {
            for (wi, ws) in project.workstreams.enumerated() {
                wsIndex[ws.id] = (pi, wi)
            }
            sortedWS[project.id] = project.workstreams.map(\.id)
        }
        cachedWorkstreamIndex = wsIndex
        cachedSortedWorkstreamIDs = sortedWS
    }

    private func totalWorkstreamCount() -> Int {
        projects.reduce(0) { $0 + $1.workstreams.count }
    }

    private func projectBinding(for id: UUID) -> Binding<Project> {
        Binding(
            get: {
                if let idx = cachedProjectIndex[id], idx < projects.count { return projects[idx] }
                return projects.first(where: { $0.id == id }) ?? Project(name: "", directory: "")
            },
            set: { newValue in
                if let idx = cachedProjectIndex[id], idx < projects.count {
                    projects[idx] = newValue
                }
            }
        )
    }

    private func projectIDByWorkstreamIDSnapshot() -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: cachedWorkstreamIndex.compactMap { workstreamID, index in
                guard projects.indices.contains(index.0) else { return nil }
                return (workstreamID, projects[index.0].id)
            }
        )
    }

    private func deferSelectionExpansion(_ selected: SidebarSelection, projectIDByWorkstreamID: [UUID: UUID], scrollProxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard selection == selected else { return }
            expandedProjects = expandedProjectIDs(
                afterSelecting: selected,
                current: expandedProjects,
                projectIDByWorkstreamID: projectIDByWorkstreamID
            )
            if reduceMotion {
                scrollProxy.scrollTo(selected, anchor: .center)
            } else {
                withAnimation(DesignMotion.interaction) {
                    scrollProxy.scrollTo(selected, anchor: .center)
                }
            }
        }
    }

    private func animateNavigationChange(_ update: () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(DesignMotion.interaction) {
                update()
            }
        }
    }

    private func toggleProjectExpansion(_ projectID: UUID) {
        animateNavigationChange {
            if expandedProjects.contains(projectID) {
                expandedProjects.remove(projectID)
            } else {
                expandedProjects.insert(projectID)
            }
        }
    }

    private func toggleOpenPRs() {
        animateNavigationChange {
            showOpenPRs.toggle()
        }
    }

    private func handleTerminalActivity(for workstreamID: UUID) {
        guard let (pi, wi) = cachedWorkstreamIndex[workstreamID] else { return }
        let now = Date()
        projects[pi].lastAccessedAt = now
        projects[pi].workstreams[wi].lastAccessedAt = now
        onProjectsChanged()
    }

    private func projectRows() -> some View {
        let projectIDByWorkstreamID = projectIDByWorkstreamIDSnapshot()
        return ForEach(cachedSortedIDs, id: \.self) { projectID in
            let projectBind = projectBinding(for: projectID)
            let project = projectBind.wrappedValue
            let hasChildren = !project.workstreams.isEmpty

            ProjectHeaderRow(
                project: project,
                isSelected: selection == .project(project.id)
                    || selection?.workstreamID.map { projectIDByWorkstreamID[$0] == project.id } == true,
                isExpanded: expandedProjects.contains(project.id),
                onToggle: hasChildren ? { toggleProjectExpansion(project.id) } : nil,
                isGitRepo: appEnv.isGitRepo(project.directory),
                githubURL: appEnv.githubURL(for: project.directory),
                onAdd: { presentNewWorkstreamSheet(for: project.id) },
                onAddWithPermissions: { addWorkstream(for: project.id, bypassPermissions: true) },
                onAddWithoutPermissions: { addWorkstream(for: project.id, bypassPermissions: false) },
                onOpenTerminal: { onOpenProjectTerminal(project.id) },
                onSetColor: { color in
                    guard let index = cachedProjectIndex[project.id], projects.indices.contains(index) else { return }
                    projects[index].color = color
                    onProjectsChanged()
                },
                onDelete: { projectToDelete = project.id }
            )
            .tag(SidebarSelection.project(project.id))

            if hasChildren && expandedProjects.contains(project.id) {
                let sortedWorkstreamIDs = cachedSortedWorkstreamIDs[project.id] ?? project.workstreams.map(\.id)
                ForEach(sortedWorkstreamIDs, id: \.self) { workstreamID in
                    if let (pIdx, wIdx) = cachedWorkstreamIndex[workstreamID],
                       projects.indices.contains(pIdx),
                       projects[pIdx].workstreams.indices.contains(wIdx)
                    {
                        let workstream = projects[pIdx].workstreams[wIdx]
                        let agentState = agentStateStore.agentState(for: workstream.id)
                        let activeSubagents = agentStateStore.activeSubagents(for: workstream.id)
                        let isChromeActive = agentStateStore.isChromeActive(for: workstream.id)
                        let isPathValid = appEnv.isPathValid(workstream.worktreePath)
                        let statusStyle = WorkstreamStatusStyle(agentState: agentState, isPathValid: isPathValid)
                        let branch = appEnv.branchName(for: workstream.worktreePath)
                        let pr = branch.flatMap { appEnv.githubPR(for: project.directory, branch: $0) }
                        WorkstreamRow(
                            name: workstream.name,
                            branchName: branch,
                            worktreePath: workstream.worktreePath,
                            agentState: agentState,
                            activeSubagents: activeSubagents,
                            isChromeActive: isChromeActive,
                            isPathValid: isPathValid,
                            isSelected: selection == .workstream(workstream.id),
                            hasActivePort: appEnv.hasActivePort(workstream.id),
                            githubURL: appEnv.githubURL(for: project.directory, branch: branch),
                            taskDescription: appEnv.taskDescription(for: workstream.worktreePath),
                            prTitle: pr?.title,
                            prNumber: pr?.number,
                            prState: pr?.state,
                            pullRequest: pr,
                            projectDirectory: project.directory,
                            stage: workstream.stage,
                            uncommittedCount: workstream.worktreePath.map { appEnv.worktreeState(for: $0).uncommittedCount } ?? 0,
                            onRemove: { workstreamToRemove = workstream.id },
                            onPurge: { confirmPurge(workstream) },
                            onRename: {
                                workstreamToRename = workstream.id
                                newWorkstreamName = workstream.name
                            },
                            onSetStage: { newStage in
                                guard let (pi, wi) = cachedWorkstreamIndex[workstream.id],
                                      projects.indices.contains(pi),
                                      projects[pi].workstreams.indices.contains(wi)
                                else { return }
                                projects[pi].workstreams[wi].stage = newStage
                                onProjectsChanged()
                            },
                            onCreateFromBranch: { baseBranch in
                                addWorkstream(for: project.id, baseBranch: baseBranch)
                            }
                        )
                        .tag(SidebarSelection.workstream(workstream.id))
                        .shortcutHint(ShortcutHint(
                            command: selection == .workstream(workstream.id) ? "[ ]" : nil,
                            commandShift: selection == .workstream(workstream.id) ? "W" : nil
                        ))
                        .padding(.leading, 28)
                        .listRowBackground(
                            Group {
                                if selection != .workstream(workstream.id) {
                                    WorkstreamRowBackground(statusStyle: statusStyle)
                                }
                            }
                        )
                    }
                }
                .onMove { source, destination in
                    moveWorkstreamRows(in: project.id, fromOffsets: source, toOffset: destination)
                }
            }
        }
        .onMove { source, destination in
            moveProjectRows(fromOffsets: source, toOffset: destination)
        }
    }

    private func moveProjectRows(fromOffsets source: IndexSet, toOffset destination: Int) {
        moveProjects(&projects, fromOffsets: source, toOffset: destination)
        cachedSortedIDs = recomputeSortedIDs()
        rebuildIndices()
        onProjectsChanged()
    }

    private func moveWorkstreamRows(in projectID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        moveWorkstreams(in: &projects, projectID: projectID, fromOffsets: source, toOffset: destination)
        rebuildIndices()
        onProjectsChanged()
    }

    /// Number of agents currently waiting on the user, for the status strip.
    private var waitingAgentCount: Int {
        var waiting = 0
        for project in projects {
            for ws in project.workstreams where agentStateStore.agentState(for: ws.id) == .waiting {
                waiting += 1
            }
        }
        return waiting
    }

    /// Collapsible section listing every open PR across all projects.
    @ViewBuilder
    private func globalPRsSection() -> some View {
        let prs = appEnv.openPullRequests(projects: projects)
        if !prs.isEmpty {
            SidebarSectionHeader(
                title: NSLocalizedString("Open PRs", comment: "Sidebar global pull requests section"),
                systemImage: "arrow.triangle.pull",
                count: prs.count,
                isExpanded: showOpenPRs,
                onToggle: toggleOpenPRs
            )
            if showOpenPRs {
                ForEach(prs) { item in
                    GlobalPRRow(
                        item: item,
                        onSelect: {
                            if let wsID = item.workstreamID { selection = .workstream(wsID) }
                        },
                        onOpenURL: {
                            if let url = URL(string: item.pr.url) { NSWorkspace.shared.open(url) }
                        }
                    )
                }
            }
        }
    }


    private var bottomBar: some View {
        VStack(spacing: 4) {
            if !projects.isEmpty {
                SidebarStatusStrip(
                    projectCount: projects.count,
                    workstreamCount: totalWorkstreamCount(),
                    openPRCount: appEnv.openPullRequests(projects: projects).count,
                    waitingCount: waitingAgentCount,
                    selectedUsageProvider: selectedUsageProvider,
                    availableUsageProviders: availableUsageProviders,
                    onPreviousUsageProvider: onPreviousUsageProvider,
                    onNextUsageProvider: onNextUsageProvider
                )
                Divider()
                    .padding(.horizontal, 8)
            }
            HStack(alignment: .center, spacing: 4) {
                Menu {
                    Button("Add Existing Directory…") { openDirectoryPicker() }
                    Button("Create New Project…") { presentNewProjectSheet() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(minWidth: 40, minHeight: 40)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Add project")
                .shortcutHint(ShortcutHint(command: "N", commandShift: "N"))
                .tourAnchor(.newProjectButton)

                Text(AppConstants.displayVersion)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                if appUpdater.isChecking || appUpdater.isUpdating {
                    ProgressView()
                        .controlSize(.mini)
                } else if appUpdater.isUpdateReady {
                    Button(action: { appUpdater.restartToApplyUpdate() }) {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Restart")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous))
                        .frame(minHeight: 40)
                    }
                    .pressable()
                    .help("Restart Dockyard to apply the installed update")
                } else if appUpdater.commitsAhead > 0 {
                    Button(action: {
                        appUpdater.applyUpdate()
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Update (\(appUpdater.commitsAhead))")
                                .tabularNumbers()
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous))
                        .frame(minHeight: 40)
                    }
                    .pressable()
                    .help("Pull latest changes from main and rebuild")
                } else {
                    Button(action: {
                        appUpdater.checkForUpdates()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .frame(minWidth: 40, minHeight: 40)
                    }
                    .pressable()
                    .foregroundStyle(.tertiary)
                    .help("Check for updates")
                }

                SidebarBottomButton(icon: "questionmark.circle") {
                    NotificationCenter.default.post(name: .openHelp, object: nil)
                }
                .accessibilityLabel("Help")
                SidebarBottomButton(icon: "gear") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    var body: some View {
        sidebar
            .alert(
                "Remove Project",
                isPresented: Binding(
                    get: { projectToDelete != nil },
                    set: { if !$0 { projectToDelete = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { projectToDelete = nil }
                Button("Remove", role: .destructive) {
                    if let id = projectToDelete {
                        deleteProject(id: id)
                    }
                }
            } message: {
                if let id = projectToDelete, let project = projects.first(where: { $0.id == id }) {
                    Text(String(format: NSLocalizedString("Remove \"%@\" from the list? Files in %@ will not be deleted.", comment: ""), project.name, project.directory))
                }
            }
            .alert(
                "Remove Workstream",
                isPresented: Binding(
                    get: { workstreamToRemove != nil },
                    set: { if !$0 { workstreamToRemove = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { workstreamToRemove = nil }
                Button("Remove", role: .destructive) {
                    performRemove()
                }
            } message: {
                Text("Ongoing terminals and Coding Agent sessions will be killed. The worktree and its files will remain on disk.")
            }
            .alert(
                "Purge Workstream",
                isPresented: Binding(
                    get: { workstreamToPurge != nil },
                    set: { if !$0 { workstreamToPurge = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { workstreamToPurge = nil }
                Button(purgeWarningMessage != nil ? "Purge Anyway" : "Purge", role: .destructive) {
                    performPurge()
                }
            } message: {
                if let warning = purgeWarningMessage {
                    Text(warning)
                } else {
                    Text("The worktree and its branch will be permanently deleted.")
                }
            }
            .alert(
                "Worktree Creation Failed",
                isPresented: $showWorktreeError
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not create the git worktree. The branch may already exist, or there may be an ongoing merge or rebase.")
            }
            .alert(
                "Not a Git Repository",
                isPresented: $showNotGitRepoError
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Workstreams require a git repository. Initialize one with git init or select a different directory.")
            }
    }

    private var sidebar: some View {
        sidebarContent
            .sheet(isPresented: $showingNewWorkstream) {
                NewWorkstreamSheet(
                    name: $configuredWorkstreamName,
                    codingCLI: $newWorkstreamCodingCLI,
                    bypassPermissions: $newWorkstreamBypassPermissions,
                    issueReference: $newWorkstreamIssue,
                    issuePreview: newWorkstreamIssuePreview,
                    issueError: newWorkstreamIssueError,
                    isLoadingIssue: isLoadingWorkstreamIssue,
                    openIssues: newWorkstreamOpenIssues,
                    isLoadingOpenIssues: isLoadingOpenIssues,
                    openIssuesError: openIssuesError,
                    canUseGitHub: appEnv.ghAvailable,
                    hasGitHubRemote: newWorkstreamProjectID.flatMap { pid in
                        projects.first(where: { $0.id == pid }).map { appEnv.hasGitHubRemote($0.directory) }
                    } ?? false,
                    onLoadIssue: loadNewWorkstreamIssue,
                    onRetryLoadIssues: {
                        if let pid = newWorkstreamProjectID, let project = projects.first(where: { $0.id == pid }) {
                            loadOpenIssues(for: project)
                        }
                    },
                    onSelectIssue: selectWorkstreamIssue,
                    onDeselectIssue: deselectWorkstreamIssue,
                    onCreate: createConfiguredWorkstream,
                    onCancel: { showingNewWorkstream = false }
                )
            }
            .sheet(isPresented: $showingNewProjectName) {
                NewProjectSheet(
                    name: $newProjectName,
                    error: $newProjectError,
                    baseDirectory: baseDirectory,
                    onAdd: { createNewProject() },
                    onCancel: { showingNewProjectName = false }
                )
            }
            .alert(
                Text("Rename Workstream"),
                isPresented: Binding(
                    get: { workstreamToRename != nil },
                    set: { if !$0 { workstreamToRename = nil } }
                )
            ) {
                TextField("New Name", text: $newWorkstreamName)
                Button("Rename") {
                    renameWorkstream()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    workstreamToRename = nil
                }
            } message: {
                Text("This will rename the git branch. Use kebab-case without spaces.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .addProject)) { _ in
                openDirectoryPicker()
            }
            .onReceive(NotificationCenter.default.publisher(for: .addNew)) { _ in
                if case let .workstream(wsID) = selection,
                   let project = projects.first(where: { $0.workstreams.contains(where: { $0.id == wsID }) })
                {
                    presentNewWorkstreamSheet(for: project.id)
                } else if case let .project(pid) = selection {
                    presentNewWorkstreamSheet(for: pid)
                } else {
                    // No selection: jump straight to the directory picker (the 99% case is
                    // adding an existing folder). Create New is Cmd+Shift+N / the + menu.
                    openDirectoryPicker()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDirectory)) { notification in
                guard let directory = notification.object as? String else { return }
                addProject(name: URL(fileURLWithPath: directory).lastPathComponent, directory: directory)
            }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        if sidebarMode == .collapsed {
            SidebarRail(
                projects: $projects,
                selection: $selection,
                appUpdater: appUpdater,
                onExpand: { setVisibleSidebarMode(.expanded) },
                onAddExistingDirectory: { openDirectoryPicker() },
                onCreateNewProject: { presentNewProjectSheet() },
                selectedUsageProvider: selectedUsageProvider,
                availableUsageProviders: availableUsageProviders
            )
            .onReceive(NotificationCenter.default.publisher(for: .terminalActivity)) { notification in
                guard let wsID = notification.object as? UUID else { return }
                handleTerminalActivity(for: wsID)
            }
            .onAppear {
                cachedSortedIDs = recomputeSortedIDs()
                rebuildIndices()
            }
        } else {
            sidebarList
        }
    }

    private var sidebarList: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                HStack {
                    Button {
                        setVisibleSidebarMode(.collapsed)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(minWidth: 40, minHeight: 40)
                    }
                    .pressable()
                    .help(NSLocalizedString("Collapse sidebar", comment: "Expanded sidebar collapse button tooltip"))
                    .accessibilityLabel("Collapse sidebar")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)

                SidebarAttentionRow(
                    attentionCount: currentAttentionCount,
                    isSelected: selection == .attention,
                    action: { selection = .attention }
                )
                .padding(.horizontal, 8)

                ScrollViewReader { scrollProxy in
                    List(selection: $selection) {
                        projectRows()
                        globalPRsSection()
                    }
                    .listStyle(.sidebar)
                    .onChange(of: selection) { _, sel in
                        guard let sel else { return }
                        deferSelectionExpansion(sel, projectIDByWorkstreamID: projectIDByWorkstreamIDSnapshot(), scrollProxy: scrollProxy)
                    }
                } // ScrollViewReader


                // Bottom bar (always visible)
                bottomBar
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalActivity)) { notification in
            guard let wsID = notification.object as? UUID else { return }
            handleTerminalActivity(for: wsID)
        }
        .onAppear {
            cachedSortedIDs = recomputeSortedIDs()
            rebuildIndices()
        }
        .onChange(of: expandedProjects) { _, newValue in SidebarState.saveExpanded(newValue) }
        .onChange(of: projects.count) { _, _ in
            cachedSortedIDs = recomputeSortedIDs()
            rebuildIndices()
        }
        .onChange(of: totalWorkstreamCount()) { _, _ in
            rebuildIndices()
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.md, style: .continuous))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Workstream management

    @AppStorage("dockyard.bypassPermissions") private var defaultBypass: Bool = false
    @AppStorage("dockyard.codingCLI") private var globalCodingCLIRaw: String = ""
    @AppStorage("dockyard.symlinkEnv") private var symlinkEnv: Bool = true

    /// Presents the creation sheet for a new workstream, initializing defaults for name,
    /// Coding Agent, and dangerous permission bypass mode based on user preferences.
    private func presentNewWorkstreamSheet(for projectID: UUID) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        guard GitOperations.isGitRepo(at: project.directory) else {
            showNotGitRepoError = true
            return
        }
        newWorkstreamProjectID = projectID
        configuredWorkstreamName = NameGenerator.generate(avoiding: Set(project.workstreams.map(\.name)))
        newWorkstreamCodingCLI = ""
        let defaultCLI = appEnv.toolStatus.resolvedCodingCLI(storedValue: globalCodingCLIRaw)
        newWorkstreamBypassPermissions = defaultBypass && defaultCLI.capabilities.supportsDangerousPermissionBypass
        newWorkstreamIssue = ""
        newWorkstreamIssuePreview = nil
        newWorkstreamIssueError = ""
        newWorkstreamOpenIssues = []
        isLoadingOpenIssues = false
        openIssuesError = ""
        issueLookupToken += 1
        showingNewWorkstream = true
        loadOpenIssues(for: project)
    }

    /// Creates and registers a workstream with the configured name, Coding Agent,
    /// permission bypass mode, and optional GitHub issue task prompt.
    private func createConfiguredWorkstream() {
        guard let projectID = newWorkstreamProjectID else { return }
        let normalizedName = NameGenerator.normalize(configuredWorkstreamName)
        guard !normalizedName.isEmpty,
              let project = projects.first(where: { $0.id == projectID }) else { return }
        let existingNames = Set(project.workstreams.map(\.name))
        var uniqueName = normalizedName
        var suffix = 2
        while existingNames.contains(uniqueName) {
            uniqueName = "\(normalizedName)-\(suffix)"
            suffix += 1
        }
        let prompt = newWorkstreamIssuePreview.map { issue in
            var text = "Implement GitHub issue #\(issue.number): \(issue.title)\n\nSource: \(issue.url.absoluteString)"
            if !issue.body.isEmpty { text += "\n\n\(issue.body)" }
            if issue.isBodyTruncated { text += "\n\n[Issue body truncated by Dockyard.]" }
            return text
        }
        if let prompt {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
        }
        showingNewWorkstream = false
        addWorkstream(
            for: projectID,
            bypassPermissions: newWorkstreamBypassPermissions,
            name: uniqueName,
            codingCLI: newWorkstreamCodingCLI.isEmpty ? nil : newWorkstreamCodingCLI,
            initialAgentPrompt: prompt
        )
    }

    private func loadNewWorkstreamIssue() {
        guard let projectID = newWorkstreamProjectID,
              let project = projects.first(where: { $0.id == projectID }),
              let ghPath = appEnv.toolStatus.gh.path
        else {
            newWorkstreamIssueError = NSLocalizedString("GitHub CLI is not available.", comment: "")
            return
        }
        let reference = newWorkstreamIssue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return }

        let cleanRef = reference.hasPrefix("#") ? String(reference.dropFirst()) : reference
        if let cached = newWorkstreamOpenIssues.first(where: { String($0.number) == cleanRef || $0.url.absoluteString == reference }) {
            selectWorkstreamIssue(cached)
            return
        }

        let repositoryURL = GitOperations.repoInfo(at: project.directory).remoteURL
            .flatMap(GitHubOperations.browserURL(from:))?
            .absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        issueLookupToken += 1
        let currentToken = issueLookupToken
        isLoadingWorkstreamIssue = true
        newWorkstreamIssueError = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let preview = GitHubOperations.issueTaskPreview(ghPath: ghPath, issue: reference, at: project.directory)
            DispatchQueue.main.async {
                guard issueLookupToken == currentToken else { return }
                isLoadingWorkstreamIssue = false
                guard let preview,
                      let repositoryURL,
                      preview.url.absoluteString.hasPrefix(repositoryURL + "/issues/")
                else {
                    newWorkstreamIssuePreview = nil
                    newWorkstreamIssueError = NSLocalizedString("Could not load that issue from the current project.", comment: "")
                    return
                }
                newWorkstreamIssuePreview = preview
                configuredWorkstreamName = workstreamName(from: preview.title, issueNumber: preview.number)
            }
        }
    }

    private func loadOpenIssues(for project: Project) {
        guard let ghPath = appEnv.toolStatus.gh.path, appEnv.ghAvailable else { return }
        guard appEnv.hasGitHubRemote(project.directory) else { return }
        let projectID = project.id
        isLoadingOpenIssues = true
        openIssuesError = ""
        let repositoryURL = GitOperations.repoInfo(at: project.directory).remoteURL
            .flatMap(GitHubOperations.browserURL(from:))?
            .absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        DispatchQueue.global(qos: .userInitiated).async {
            let issues = GitHubOperations.openIssues(ghPath: ghPath, at: project.directory, limit: 30)
            DispatchQueue.main.async {
                guard newWorkstreamProjectID == projectID else { return }
                isLoadingOpenIssues = false
                guard let issues else {
                    openIssuesError = NSLocalizedString("Could not load open issues.", comment: "")
                    return
                }
                let filtered = issues.filter { issue in
                    guard let repositoryURL else { return true }
                    return issue.url.absoluteString.hasPrefix(repositoryURL + "/issues/")
                }
                newWorkstreamOpenIssues = filtered
            }
        }
    }

    private func selectWorkstreamIssue(_ issue: GitHubIssueTaskPreview) {
        issueLookupToken += 1
        isLoadingWorkstreamIssue = false
        newWorkstreamIssuePreview = issue
        newWorkstreamIssueError = ""
        configuredWorkstreamName = workstreamName(from: issue.title, issueNumber: issue.number)
    }

    private func deselectWorkstreamIssue() {
        issueLookupToken += 1
        isLoadingWorkstreamIssue = false
        newWorkstreamIssuePreview = nil
        newWorkstreamIssueError = ""
        if let projectID = newWorkstreamProjectID, let project = projects.first(where: { $0.id == projectID }) {
            configuredWorkstreamName = NameGenerator.generate(avoiding: Set(project.workstreams.map(\.name)))
        }
    }

    private func workstreamName(from title: String, issueNumber: Int) -> String {
        let collapsed = NameGenerator.normalize(title, maximumLength: 48)
        let suffix = collapsed.isEmpty ? "issue" : collapsed
        return "issue-\(issueNumber)-\(suffix)"
    }

    private func addWorkstream(
        for projectID: UUID,
        bypassPermissions: Bool? = nil,
        baseBranch: String? = nil,
        name requestedName: String? = nil,
        codingCLI: String? = nil,
        initialAgentPrompt: String? = nil
    ) {
        logger.warning("[Dockyard] addWorkstream called for projectID=\(projectID, privacy: .public)")
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
            logger.warning("[Dockyard] addWorkstream: project not found")
            return
        }
        let project = projects[index]
        logger.warning("[Dockyard] addWorkstream: project=\(project.name, privacy: .public) dir=\(project.directory, privacy: .public)")

        guard GitOperations.isGitRepo(at: project.directory) else {
            logger.warning("[Dockyard] addWorkstream: not a git repo")
            showNotGitRepoError = true
            return
        }
        logger.warning("[Dockyard] addWorkstream: is git repo")

        let existingNames = Set(project.workstreams.map(\.name))
        let name = requestedName ?? NameGenerator.generate(avoiding: existingNames)
        logger.warning("[Dockyard] addWorkstream: generated name=\(name, privacy: .public)")

        let bypass = bypassPermissions ?? defaultBypass
        let workstream = Workstream(
            name: name,
            worktreePath: nil,
            bypassPermissions: bypass,
            codingCLI: codingCLI,
            initialAgentPrompt: initialAgentPrompt
        )
        expandedProjects.insert(projectID)
        NotificationCenter.default.post(
            name: .workstreamCreated,
            object: nil,
            userInfo: ["projectID": projectID, "workstream": workstream]
        )
        rebuildIndices()
        logger.warning("[Dockyard] addWorkstream: posted notification (optimistic), starting background worktree creation")

        let projectPath = project.directory
        let projectName = project.name
        let prefix = branchPrefix
        let symlink = symlinkEnv
        let workstreamID = workstream.id

        DispatchQueue.global(qos: .userInitiated).async {
            let worktreePath = GitOperations.createWorktree(
                projectPath: projectPath,
                projectName: projectName,
                workstreamName: name,
                branchPrefix: prefix,
                symlinkEnv: symlink,
                baseBranch: baseBranch
            )
            DispatchQueue.main.async {
                if let worktreePath {
                    logger.warning("[Dockyard] addWorkstream: worktree created at \(worktreePath, privacy: .public)")
                    NotificationCenter.default.post(
                        name: .workstreamWorktreeReady,
                        object: nil,
                        userInfo: ["workstreamID": workstreamID, "worktreePath": worktreePath]
                    )
                } else {
                    logger.warning("[Dockyard] addWorkstream: createWorktree FAILED, rolling back")
                    NotificationCenter.default.post(
                        name: .workstreamCreationFailed,
                        object: nil,
                        userInfo: ["projectID": projectID, "workstreamID": workstreamID]
                    )
                    showWorktreeError = true
                }
            }
        }
    }

    @EnvironmentObject private var surfaceCache: TerminalSurfaceCache
    @EnvironmentObject private var appEnv: AppEnvironment
    @EnvironmentObject private var activityTracker: WorkstreamActivityTracker
    @EnvironmentObject private var agentStateStore: AgentStateStore

    private var currentAttentionCount: Int {
        projects
            .flatMap(\.workstreams)
            .filter { agentStateStore.agentState(for: $0.id) == .waiting }
            .count
    }

    private func renameWorkstream() {
        guard let wsID = workstreamToRename,
              let pi = projects.firstIndex(where: { $0.workstreams.contains(where: { $0.id == wsID }) }),
              let wi = projects[pi].workstreams.firstIndex(where: { $0.id == wsID })
        else {
            workstreamToRename = nil
            return
        }

        let newName = newWorkstreamName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            workstreamToRename = nil
            return
        }

        let workstream = projects[pi].workstreams[wi]
        if let worktreePath = workstream.worktreePath, appEnv.isPathValid(worktreePath) {
            let currentBranch = appEnv.branchName(for: worktreePath) ?? workstream.name
            let prefix = currentBranch.contains("/") ? String(currentBranch.split(separator: "/").dropLast().joined(separator: "/")) + "/" : ""
            let newBranchName = prefix + newName

            if GitOperations.renameBranch(at: worktreePath, to: newBranchName) {
                projects[pi].workstreams[wi].name = newName
                ProjectStore.save(projects)
                appEnv.refreshAllRepoInfo(projects: projects)
            }
        }
        workstreamToRename = nil
    }

    private func confirmPurge(_ workstream: Workstream) {
        purgeWarningMessage = WorkstreamArchiver.purgeWarning(for: workstream)
        workstreamToPurge = workstream.id
    }

    private func performRemove() {
        guard let wsID = workstreamToRemove,
              let pi = projects.firstIndex(where: { $0.workstreams.contains(where: { $0.id == wsID }) }) else { return }
        let projectID = projects[pi].id
        WorkstreamArchiver.remove(wsID, in: &projects[pi], surfaceCache: surfaceCache, tmuxPath: appEnv.toolStatus.tmux.path)
        rebuildIndices()
        if case let .workstream(id) = selection, id == wsID {
            selection = projects[pi].workstreams.first.map { .workstream($0.id) } ?? .project(projectID)
        }
        onProjectsChanged()
        workstreamToRemove = nil
    }

    private func performPurge() {
        guard let wsID = workstreamToPurge,
              let pi = projects.firstIndex(where: { $0.workstreams.contains(where: { $0.id == wsID }) }) else { return }
        let projectID = projects[pi].id
        WorkstreamArchiver.purge(wsID, in: &projects[pi], surfaceCache: surfaceCache, tmuxPath: appEnv.toolStatus.tmux.path)
        rebuildIndices()
        if case let .workstream(id) = selection, id == wsID {
            selection = projects[pi].workstreams.first.map { .workstream($0.id) } ?? .project(projectID)
        }
        onProjectsChanged()
        workstreamToPurge = nil
    }

    // MARK: - Project management

    private func deleteProject(id: UUID) {
        if let project = projects.first(where: { $0.id == id }) {
            for ws in project.workstreams {
                surfaceCache.removeWorkstreamSurfaces(for: ws.id)
            }
        }
        surfaceCache.removeProjectRootSurface(for: id)
        projects.removeAll { $0.id == id }
        if case let .project(pid) = selection, pid == id { selection = nil }
        if case let .workstream(wsID) = selection,
           !projects.contains(where: { $0.workstreams.contains(where: { $0.id == wsID }) })
        {
            selection = nil
        }
        projectToDelete = nil
        onProjectsChanged()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.hasDirectoryPath || FileManager.default.isDirectory(at: url) else { return }

                DispatchQueue.main.async {
                    addProject(name: url.lastPathComponent, directory: url.path)
                }
            }
        }
        return true
    }

    @AppStorage("dockyard.baseDirectory") private var baseDirectory: String = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
    @AppStorage("dockyard.branchPrefix") private var branchPrefix: String = "dy"

    private func presentNewProjectSheet() {
        newProjectName = ""
        newProjectError = ""
        showingNewProjectName = true
    }

    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: baseDirectory)
        panel.message = NSLocalizedString("Choose a project directory", comment: "")
        panel.prompt = NSLocalizedString("Select", comment: "")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.addProject(name: url.lastPathComponent, directory: url.path)
        }
    }

    private func createNewProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let dirURL = URL(fileURLWithPath: baseDirectory).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dirURL.path) {
            newProjectError = NSLocalizedString("A file or directory with this name already exists.", comment: "")
            return
        }

        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            newProjectError = error.localizedDescription
            return
        }

        // Initialize git repo in the new directory
        _ = GitOperations.initRepo(at: dirURL.path)

        showingNewProjectName = false
        addProject(name: name, directory: dirURL.path)
    }

    private func addProject(name: String, directory: String) {
        // Resolve worktree branches to their main repository
        let resolvedDirectory: String
        let resolvedName: String
        if let mainRepoPath = GitOperations.mainRepositoryPath(for: directory) {
            resolvedDirectory = mainRepoPath
            resolvedName = URL(fileURLWithPath: mainRepoPath).lastPathComponent
        } else {
            resolvedDirectory = directory
            resolvedName = name
        }

        if let existing = projects.first(where: { $0.directory == resolvedDirectory }) {
            selection = .project(existing.id)
            return
        }

        let projectName = resolvedName.isEmpty ? URL(fileURLWithPath: resolvedDirectory).lastPathComponent : resolvedName
        let project = Project(name: projectName, directory: resolvedDirectory)
        NotificationCenter.default.post(
            name: .projectCreated,
            object: nil,
            userInfo: ["project": project]
        )
    }
}

extension FileManager {
    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

func copyTextToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Opens a directory in the user's configured terminal, falling back to Apple Terminal.
func openDirectoryInTerminal(_ directory: String) {
    let terminalBundleID = UserDefaults.standard.string(forKey: "dockyard.defaultTerminal") ?? ""
    let appURL: URL?
    if !terminalBundleID.isEmpty {
        appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleID)
    } else {
        appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    }
    guard let appURL else { return }
    let config = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.open([URL(fileURLWithPath: directory)], withApplicationAt: appURL, configuration: config)
}

private struct ProjectHeaderRow: View {
    let project: Project
    let isSelected: Bool
    let isExpanded: Bool
    let onToggle: (() -> Void)?
    let isGitRepo: Bool
    var githubURL: URL?
    let onAdd: () -> Void
    let onAddWithPermissions: () -> Void
    let onAddWithoutPermissions: () -> Void
    let onOpenTerminal: () -> Void
    let onSetColor: (ProjectColor?) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isChevronHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Group {
                if onToggle != nil {
                    Button(action: { onToggle?() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isChevronHovering ? .primary : .secondary)
                            .frame(width: 22, height: 22)
                            .background(isChevronHovering ? Color.primary.opacity(0.1) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                            .frame(minWidth: 40, minHeight: 40)
                    }
                    .pressable()
                    .onHover { isChevronHovering = $0 }
                    .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
                    .accessibilityValue(isExpanded ? "expanded" : "collapsed")
                } else {
                    Color.clear
                }
            }
            .frame(width: 22)

            Circle()
                .fill(project.color?.swiftUIColor ?? Color.clear)
                .frame(width: 7, height: 7)
                .overlay {
                    if project.color != nil {
                        Circle().stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
                    }
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))

                    if !project.workstreams.isEmpty {
                        Text("\(project.workstreams.count)")
                            .font(.system(size: 9, weight: .medium))
                            .tabularNumbers()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                            .accessibilityLabel("\(project.workstreams.count) workstreams")
                    }
                }

                Text(project.directory.abbreviatedPath)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                if isGitRepo {
                    SidebarIconButton(icon: "plus", action: onAdd)
                        .accessibilityLabel("Add workstream to \(project.name)")
                        .contextMenu {
                            Button(action: onAddWithPermissions) {
                                Label("New workstream (dangerous permissions)", systemImage: "lock.open")
                            }
                            Button(action: onAddWithoutPermissions) {
                                Label("New workstream (with prompts)", systemImage: "lock.shield")
                            }
                        }
                }
                SidebarIconButton(icon: "terminal", action: onOpenTerminal)
                    .accessibilityLabel("Open project terminal")
                    .help("Open project terminal")
                SidebarIconButton(icon: "trash", action: onDelete)
                    .accessibilityLabel("Remove project")
            }
            .opacity(isHovering ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .hoverHighlight(radius: DesignRadius.md)
        .shortcutHint(ShortcutHint(command: isSelected ? "↑ ↓" : nil))
        .tourAnchor(.newWorkstreamButton, enabled: isSelected)
        .contextMenu {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.directory)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Button {
                openDirectoryInTerminal(project.directory)
            } label: {
                Label("Open in External Terminal", systemImage: "terminal")
            }
            if let githubURL {
                Button {
                    NSWorkspace.shared.open(githubURL)
                } label: {
                    Label("Open on GitHub", image: "github")
                }
            }
            Divider()
            Button {
                copyTextToPasteboard(project.directory)
            } label: {
                Label("Copy project path", systemImage: "doc.on.doc")
            }
            Divider()
            Menu("Project Color") {
                Button {
                    onSetColor(nil)
                } label: {
                    Label("No Color", systemImage: project.color == nil ? "checkmark.circle.fill" : "circle")
                }
                Divider()
                ForEach(ProjectColor.allCases) { color in
                    Button {
                        onSetColor(color)
                    } label: {
                        Label {
                            Text(color.localizedName)
                        } icon: {
                            Image(systemName: project.color == color ? "checkmark.circle.fill" : "circle.fill")
                                .foregroundStyle(color.swiftUIColor)
                        }
                    }
                }
            }
        }
    }
}

enum WorkstreamStatusColor: Equatable {
    case primary
    case secondary
    case tertiary
    case selected
    case green
    case blue
    case orange

    func shapeStyle(opacity: Double = 1) -> AnyShapeStyle {
        switch self {
        case .primary:
            return AnyShapeStyle(Color.primary.opacity(opacity))
        case .secondary:
            return AnyShapeStyle(Color.secondary.opacity(opacity))
        case .tertiary:
            return opacity == 1 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.secondary.opacity(0.5 * opacity))
        case .selected:
            return AnyShapeStyle(Color(nsColor: .selectedControlTextColor).opacity(opacity))
        case .green:
            return AnyShapeStyle(DesignColor.statusSuccess.opacity(opacity))
        case .blue:
            return AnyShapeStyle(DesignColor.statusInfo.opacity(opacity))
        case .orange:
            return AnyShapeStyle(DesignColor.statusWarning.opacity(opacity))
        }
    }

    func tintColor(opacity: Double = 1) -> Color? {
        switch self {
        case .primary, .secondary, .tertiary, .selected:
            return nil
        case .green:
            return DesignColor.statusSuccess.opacity(opacity)
        case .blue:
            return DesignColor.statusInfo.opacity(opacity)
        case .orange:
            return DesignColor.statusWarning.opacity(opacity)
        }
    }
}

struct WorkstreamStatusStyle: Equatable {
    enum IndicatorShape: Equatable {
        case none
        case circle
        case warningTriangle
    }

    let indicatorShape: IndicatorShape
    let indicatorColor: WorkstreamStatusColor?
    let indicatorSize: CGFloat
    let pulses: Bool
    let labelColor: WorkstreamStatusColor
    let subtitleColor: WorkstreamStatusColor
    let subtitleOpacity: Double
    let rowTintColor: WorkstreamStatusColor?
    let rowTintOpacity: Double

    init(agentState: AgentState?, isPathValid: Bool) {
        if !isPathValid {
            indicatorShape = .warningTriangle
            indicatorColor = .orange
            indicatorSize = 10
            pulses = false
            labelColor = .secondary
            subtitleColor = .tertiary
            subtitleOpacity = 1
            rowTintColor = nil
            rowTintOpacity = 0
            return
        }

        switch agentState {
        case .working:
            indicatorShape = .circle
            indicatorColor = .green
            indicatorSize = 6
            pulses = true
            labelColor = .primary
            subtitleColor = .tertiary
            subtitleOpacity = 1
            rowTintColor = nil
            rowTintOpacity = 0
        case .waiting:
            indicatorShape = .circle
            indicatorColor = .blue
            indicatorSize = 6
            pulses = false
            labelColor = .blue
            subtitleColor = .blue
            subtitleOpacity = 0.8
            rowTintColor = nil
            rowTintOpacity = 0
        case .idle:
            indicatorShape = .circle
            indicatorColor = .tertiary
            indicatorSize = 5
            pulses = false
            labelColor = .primary
            subtitleColor = .tertiary
            subtitleOpacity = 1
            rowTintColor = nil
            rowTintOpacity = 0
        case nil:
            indicatorShape = .none
            indicatorColor = nil
            indicatorSize = 0
            pulses = false
            labelColor = .primary
            subtitleColor = .tertiary
            subtitleOpacity = 1
            rowTintColor = nil
            rowTintOpacity = 0
        }
    }

    var labelStyle: AnyShapeStyle {
        labelColor.shapeStyle()
    }

    var subtitleStyle: AnyShapeStyle {
        subtitleColor.shapeStyle(opacity: subtitleOpacity)
    }
}

struct WorkstreamRowForegroundStyle: Equatable {
    let labelColor: WorkstreamStatusColor
    let subtitleColor: WorkstreamStatusColor
    let subtitleOpacity: Double
    let contentOpacity: Double

    init(statusStyle: WorkstreamStatusStyle, stageStyle: WorkstreamStageStyle, isSelected: Bool) {
        if isSelected {
            // A sidebar List can use any macOS accent color for its selection
            // background. Keep every text-bearing state on the system's
            // selected-control foreground instead of stacking muted/status
            // colors over that background.
            labelColor = .selected
            subtitleColor = .selected
            subtitleOpacity = 1
            contentOpacity = 1
        } else {
            labelColor = stageStyle.recedesRow ? .secondary : statusStyle.labelColor
            subtitleColor = stageStyle.recedesRow ? .secondary : statusStyle.subtitleColor
            subtitleOpacity = stageStyle.recedesRow ? 1 : statusStyle.subtitleOpacity
            contentOpacity = stageStyle.recedesRow ? 0.65 : 1
        }
    }

    var labelStyle: AnyShapeStyle {
        labelColor.shapeStyle()
    }

    var subtitleStyle: AnyShapeStyle {
        subtitleColor.shapeStyle(opacity: subtitleOpacity)
    }
}

private struct WorkstreamRowBackground: View {
    let statusStyle: WorkstreamStatusStyle

    var body: some View {
        Group {
            if let rowTintColor = statusStyle.rowTintColor,
               let tintColor = rowTintColor.tintColor(opacity: statusStyle.rowTintOpacity)
            {
                tintColor
                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct WorkstreamRow: View {
    let name: String
    var branchName: String?
    var worktreePath: String?
    var agentState: AgentState? = nil
    var activeSubagents: [AgentSubagentSnapshot] = []
    var isChromeActive: Bool = false
    var isPathValid: Bool = false
    var isSelected: Bool = false
    var hasActivePort: Bool = false
    var githubURL: URL?
    var taskDescription: String?
    var prTitle: String?
    var prNumber: Int?
    var prState: String?
    var pullRequest: GitHubPR?
    var projectDirectory: String = ""
    var stage: WorkstreamStage = .auto
    var uncommittedCount: Int = 0
    let onRemove: () -> Void
    let onPurge: () -> Void
    var onRename: (() -> Void)? = nil
    var onSetStage: ((WorkstreamStage) -> Void)? = nil
    var onCreateFromBranch: ((String) -> Void)? = nil

    @State private var isHovering = false

    private var headline: String {
        if let prTitle { return prTitle }
        if let taskDescription { return taskDescription }
        return name
    }

    private var hasRichHeadline: Bool {
        prTitle != nil || taskDescription != nil
    }

    private var subtitle: String? {
        guard isPathValid else { return nil }
        if hasRichHeadline {
            return branchName ?? name
        }
        if let branchName, branchName != name {
            return branchName
        }
        return nil
    }

    /// Show a compact dirty hint (e.g. `±3`) for valid worktrees with uncommitted changes.
    private var dirtyCount: Int {
        isPathValid ? uncommittedCount : 0
    }

    private var displayStage: WorkstreamDisplayStage {
        stage.displayStage(prState: prState)
    }

    private var stageStyle: WorkstreamStageStyle {
        WorkstreamStageStyle(
            displayStage: displayStage,
            isManuallySet: stage != .auto,
            prNumber: prNumber,
            pullRequest: pullRequest
        )
    }

    private var statusStyle: WorkstreamStatusStyle {
        WorkstreamStatusStyle(agentState: agentState, isPathValid: isPathValid)
    }

    private var foregroundStyle: WorkstreamRowForegroundStyle {
        WorkstreamRowForegroundStyle(
            statusStyle: statusStyle,
            stageStyle: stageStyle,
            isSelected: isSelected
        )
    }

    private var contentOpacity: Double {
        foregroundStyle.contentOpacity
    }

    private var labelStyle: AnyShapeStyle {
        foregroundStyle.labelStyle
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if isSelected {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                    Color.accentColor.opacity(0.10)
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                rowContent
                if (isSelected && (agentState != nil || !activeSubagents.isEmpty)) || !activeSubagents.isEmpty {
                    agentFleet
                }
            }
            .padding(.leading, isSelected ? 6 : 0)
            .padding(.vertical, isSelected ? 4 : (activeSubagents.isEmpty ? 0 : 2))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(taskDescription ?? "")
        .onHover { isHovering = $0 }
        .hoverHighlight(radius: DesignRadius.md)
        .tourAnchor(.selectedWorkstreamRow, enabled: isSelected)
        .contextMenu {
            if let worktreePath {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktreePath)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button {
                    openDirectoryInTerminal(worktreePath)
                } label: {
                    Label("Open in External Terminal", systemImage: "terminal")
                }
            }
            if let githubURL {
                Button {
                    NSWorkspace.shared.open(githubURL)
                } label: {
                    Label("Open on GitHub", image: "github")
                }
            }
            if worktreePath != nil || githubURL != nil {
                Divider()
            }
            if let branchName, let onCreateFromBranch {
                Button {
                    onCreateFromBranch(branchName)
                } label: {
                    Label("New workstream from this branch", systemImage: "arrow.triangle.branch")
                }
                Divider()
            }
            if let onSetStage {
                Menu {
                    stageMenuButton(.auto, titleKey: "Auto", onSetStage: onSetStage)
                    Divider()
                    stageMenuButton(.working, titleKey: "Still working", onSetStage: onSetStage)
                    stageMenuButton(.review, titleKey: "Needs review", onSetStage: onSetStage)
                    stageMenuButton(.done, titleKey: "Done / merged", onSetStage: onSetStage)
                } label: {
                    Label("Status", systemImage: "tag")
                }
                Divider()
            }
            if let onRename {
                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                }
            }
            if let branchName {
                Button {
                    copyTextToPasteboard(branchName)
                } label: {
                    Label("Copy branch name", systemImage: "arrow.triangle.branch")
                }
            }
            if let worktreePath {
                Button {
                    copyTextToPasteboard(worktreePath)
                } label: {
                    Label("Copy worktree path", systemImage: "doc.on.doc")
                }
            }
            Divider()
            Button(action: onRemove) {
                Label("Remove", systemImage: "xmark")
            }
            Button(role: .destructive, action: onPurge) {
                Label("Purge", systemImage: "trash")
            }
        }
    }

    private func stageMenuButton(_ option: WorkstreamStage, titleKey: LocalizedStringKey, onSetStage: @escaping (WorkstreamStage) -> Void) -> some View {
        Button {
            onSetStage(option)
        } label: {
            if stage == option {
                Label(titleKey, systemImage: "checkmark")
            } else {
                Text(titleKey)
            }
        }
    }

    private var subtitleStyle: AnyShapeStyle {
        foregroundStyle.subtitleStyle
    }

    private var rowContent: some View {
        HStack(spacing: 4) {
            ActivityIndicator(state: agentState, isPathValid: isPathValid)
                .opacity(contentOpacity)

            if isChromeActive {
                Image(systemName: "globe")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignColor.statusInfo)
                    .accessibilityLabel("Claude in Chrome is active")
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(headline)
                        .font(.system(size: 12))
                        .strikethrough(!isPathValid)
                        .foregroundStyle(labelStyle)
                        .lineLimit(1)
                    if hasActivePort {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(DesignColor.statusSuccess)
                    }
                }
                if subtitle != nil || dirtyCount > 0 {
                    HStack(spacing: 3) {
                        if let subtitle {
                            Text(subtitle)
                                .lineLimit(1)
                        }
                        if dirtyCount > 0 {
                            Text("±\(dirtyCount)")
                                .tabularNumbers()
                                .foregroundStyle(subtitleStyle)
                                .help(NSLocalizedString("Uncommitted changes", comment: ""))
                        }
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(subtitleStyle)
                }
            }
            .layoutPriority(-1)
            .opacity(contentOpacity)

            Spacer()

            if let pullRequest, pullRequest.hasConflicts {
                ConflictBadge(url: URL(string: pullRequest.url))
            }

            if let pill = stageStyle.stagePill {
                if let pullRequest, let url = URL(string: pullRequest.url) {
                    Link(destination: url) {
                        StagePill(style: pill).frame(minHeight: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open on GitHub")
                } else {
                    StagePill(style: pill)
                        .opacity(contentOpacity * (isHovering ? 0.75 : 1))
                }
            }
            if let pullRequest {
                PRChecksBadge(pr: pullRequest, directory: projectDirectory, compact: true)
            }

            SidebarIconButton(icon: "xmark", action: onRemove)
                .accessibilityLabel("Remove workstream")
                .opacity(isHovering ? 1 : 0)
        }
    }

    private var agentFleet: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let agentState {
                agentLine(
                    systemImage: "sparkles",
                    title: NSLocalizedString("Coding Agent", comment: "Main agent label in selected workstream"),
                    state: agentState
                )
            }
            ForEach(activeSubagents.prefix(4), id: \.agentID) { subagent in
                agentLine(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    title: subagent.agentType,
                    state: .working
                )
            }
            if activeSubagents.count > 4 {
                let remainingCount = activeSubagents.count - 4
                let remainingText = remainingCount == 1
                    ? NSLocalizedString("1 more agent", comment: "One more active subagent")
                    : String(
                        format: NSLocalizedString("%d more agents", comment: "Additional active subagents in selected workstream"),
                        remainingCount
                    )
                Text(remainingText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
        }
        .padding(.leading, 16)
        .padding(.bottom, 3)
    }

    private func agentLine(systemImage: String, title: String, state: AgentState) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(state == .waiting ? DesignColor.statusWarning : DesignColor.statusSuccess)
                .frame(width: 11)
            Text(title)
                .font(.system(size: 10))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(agentStateLabel(state))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isSelected ? Color(nsColor: .selectedControlTextColor).opacity(0.82) : Color.primary.opacity(0.82))
    }

    private func agentStateLabel(_ state: AgentState) -> LocalizedStringKey {
        switch state {
        case .working: "Working"
        case .waiting: "Waiting"
        case .idle: "Ready"
        }
    }
}

struct ConflictBadge: View {
    var url: URL? = nil

    var body: some View {
        let content = HStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .bold))
            Text("Conflicts")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(DesignColor.statusError)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(DesignColor.statusError.opacity(0.14), in: RoundedRectangle(cornerRadius: DesignRadius.sm))
        .help(NSLocalizedString("Merge conflicts with base branch", comment: ""))
        .accessibilityLabel(NSLocalizedString("Merge conflicts with base branch", comment: ""))

        if let url {
            Link(destination: url) {
                content.frame(minHeight: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

private struct StagePill: View {
    let style: WorkstreamStagePillStyle

    private var baseColor: Color {
        style.tintColor ?? DesignColor.statusMerged
    }

    private var foregroundColor: Color {
        switch style.appearance {
        case .filled:
            return .white
        case .outline, .bare:
            return baseColor.opacity(0.85)
        }
    }

    private var fillColor: Color {
        style.appearance == .filled ? baseColor : Color.clear
    }

    private var strokeColor: Color {
        switch style.appearance {
        case .filled:
            return Color.clear
        case .outline:
            return baseColor.opacity(0.5)
        case .bare:
            return baseColor.opacity(0.35)
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if style.showsManualMark {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7, weight: .semibold))
            }
            if let iconSystemName = style.iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(LocalizedStringKey(style.titleKey))
            if let prNumber = style.prNumber {
                Text("#\(prNumber)")
                    .tabularNumbers()
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(fillColor)
        )
        .overlay(
            Capsule()
                .stroke(strokeColor, lineWidth: 1)
        )
        .help(NSLocalizedString("Workstream lifecycle status", comment: ""))
    }
}

struct ActivityIndicator: View {
    let state: AgentState?
    let isPathValid: Bool

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var statusStyle: WorkstreamStatusStyle {
        WorkstreamStatusStyle(agentState: state, isPathValid: isPathValid)
    }

    var body: some View {
        Group {
            if statusStyle.indicatorShape == .warningTriangle {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(statusStyle.indicatorColor?.shapeStyle() ?? AnyShapeStyle(.tertiary))
                    .font(.system(size: 10))
            } else if statusStyle.indicatorShape == .circle, let indicatorColor = statusStyle.indicatorColor {
                Circle()
                    .foregroundStyle(indicatorColor.shapeStyle())
                    .frame(width: statusStyle.indicatorSize, height: statusStyle.indicatorSize)
                    .opacity(statusStyle.pulses && isPulsing ? 0.4 : 1.0)
                    .animation(
                        reduceMotion || !statusStyle.pulses ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = statusStyle.pulses }
                    .onChange(of: statusStyle.pulses) { _, pulses in
                        isPulsing = pulses
                    }
            }
            // state == nil (unknown) draws nothing
        }
        .frame(width: 12)
    }
}

/// Collapsible header row for an auxiliary sidebar section (Open PRs).
private struct SidebarSectionHeader: View {
    let title: String
    let systemImage: String
    var count: Int?
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .offset(y: 0.5)
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced))
                        .tabularNumbers()
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .frame(minHeight: 40)
        .pressable()
        .listRowSeparator(.hidden)
        .hoverHighlight(radius: DesignRadius.md)
    }
}

/// A single global Open-PRs row: click to jump to its workstream, GitHub icon to open it.
private struct GlobalPRRow: View {
    let item: OpenPRItem
    let onSelect: () -> Void
    let onOpenURL: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text("#\(item.pr.number)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tabularNumbers()
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.pr.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Text(item.projectName)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer()
            if item.pr.hasConflicts {
                ConflictBadge(url: URL(string: item.pr.url))
            }
            if let pill = item.pr.stagePill(isManuallySet: false, includeNumber: false) {
                StagePill(style: pill)
            }
            SidebarIconButton(icon: "arrow.up.right.square", action: onOpenURL)
                .opacity(isHovering ? 1 : 0)
            PRChecksBadge(pr: item.pr, directory: item.projectDirectory, compact: true)
        }
        .padding(.leading, 16)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .hoverHighlight(radius: DesignRadius.md)
        .help(item.pr.title)
    }
}


private struct SidebarIconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 22, height: 22)
                .background(isHovering ? Color.primary.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                .frame(minWidth: 40, minHeight: 40)
        }
        .pressable()
        .onHover { isHovering = $0 }
    }
}

private struct SidebarBottomButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background(isHovering ? Color.primary.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
                .frame(minWidth: 40, minHeight: 40)
        }
        .pressable()
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private struct NewWorkstreamSheet: View {
    @Binding var name: String
    @Binding var codingCLI: String
    @Binding var bypassPermissions: Bool
    @Binding var issueReference: String
    let issuePreview: GitHubIssueTaskPreview?
    let issueError: String
    let isLoadingIssue: Bool
    let openIssues: [GitHubIssueTaskPreview]
    let isLoadingOpenIssues: Bool
    let openIssuesError: String
    let canUseGitHub: Bool
    let hasGitHubRemote: Bool
    let onLoadIssue: () -> Void
    let onRetryLoadIssues: () -> Void
    let onSelectIssue: (GitHubIssueTaskPreview) -> Void
    let onDeselectIssue: () -> Void
    let onCreate: () -> Void
    let onCancel: () -> Void

    @AppStorage("dockyard.codingCLI") private var globalCodingCLIRaw: String = ""
    @EnvironmentObject private var appEnv: AppEnvironment

    private var effectiveCodingCLI: CodingCLI {
        let effectiveRaw = effectiveCodingCLIRaw(workstream: codingCLI, global: globalCodingCLIRaw)
        return appEnv.toolStatus.resolvedCodingCLI(storedValue: effectiveRaw)
    }

    private var supportsDangerousPermissionBypass: Bool {
        effectiveCodingCLI.capabilities.supportsDangerousPermissionBypass
    }

    private func permissionDescription(for cli: CodingCLI) -> String {
        switch cli {
        case .claude:
            return NSLocalizedString("Claude Code will start with bypassPermissions.", comment: "")
        case .codex:
            return NSLocalizedString("Codex will bypass approvals and sandboxing.", comment: "")
        case .agy:
            return NSLocalizedString("Antigravity CLI will start with --dangerously-skip-permissions (YOLO mode).", comment: "")
        case .opencode:
            return ""
        }
    }

    private var filteredIssues: [GitHubIssueTaskPreview] {
        let trimmed = issueReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return openIssues }

        let cleanNumber = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        return openIssues.filter { issue in
            if String(issue.number) == cleanNumber || String(issue.number).contains(cleanNumber) {
                return true
            }
            return issue.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Workstream")
                .font(.headline)

            Form {
                TextField("Workstream Name", text: $name)
                Picker("Coding Agent", selection: $codingCLI) {
                    Text("Project Default").tag("")
                    ForEach(CodingCLI.allCases) { cli in
                        Text(cli.displayName).tag(cli.rawValue)
                    }
                }
                .onChange(of: codingCLI) { _ in
                    if !supportsDangerousPermissionBypass {
                        bypassPermissions = false
                    }
                }

                Toggle("Dangerously skip permissions", isOn: $bypassPermissions)
                    .disabled(!supportsDangerousPermissionBypass)

                if !supportsDangerousPermissionBypass {
                    Text(String(format: NSLocalizedString("Dangerous permission mode is not supported by %@.", comment: ""), effectiveCodingCLI.displayName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if bypassPermissions {
                    Text(permissionDescription(for: effectiveCodingCLI))
                        .font(.caption)
                        .foregroundStyle(DesignColor.statusWarning)
                }

                Section("GitHub Issue") {
                    if !canUseGitHub {
                        Text("Install and authenticate the GitHub CLI to link an issue.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !hasGitHubRemote {
                        Text("This repository does not have a GitHub remote.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.tertiary)
                                    .font(.system(size: 11))
                                TextField("Search issues or enter # / URL", text: $issueReference)
                                    .textFieldStyle(.plain)
                                    .onSubmit(onLoadIssue)
                                if !issueReference.isEmpty {
                                    Button {
                                        issueReference = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )

                            if isLoadingIssue {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button("Load", action: onLoadIssue)
                                    .disabled(issueReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }

                        if isLoadingOpenIssues {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading open issues...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        } else if !openIssuesError.isEmpty {
                            HStack(spacing: 6) {
                                Text(openIssuesError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                Spacer()
                                Button("Retry", action: onRetryLoadIssues)
                                    .font(.caption)
                                    .buttonStyle(.link)
                            }
                            .padding(.vertical, 4)
                        } else if !openIssues.isEmpty {
                            let filtered = filteredIssues
                            if filtered.isEmpty {
                                Text("No matching issues")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 2) {
                                        ForEach(filtered) { issue in
                                            IssueRowView(
                                                issue: issue,
                                                isSelected: issuePreview?.number == issue.number,
                                                onSelect: {
                                                    if issuePreview?.number == issue.number {
                                                        onDeselectIssue()
                                                    } else {
                                                        onSelectIssue(issue)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(2)
                                }
                                .frame(minHeight: 0, maxHeight: 130)
                            }
                        } else {
                            Text("No open issues found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }

                        if let issuePreview {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("#\(issuePreview.number) · \(issuePreview.title)")
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: onDeselectIssue) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(Text("Clear issue"))
                                }
                                if !issuePreview.body.isEmpty {
                                    Text(issuePreview.body)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                        } else if !issueError.isEmpty {
                            Text(issueError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingIssue)
            }
        }
        .padding(20)
        .frame(width: 480, height: 560)
    }
}

private struct IssueRowView: View {
    let issue: GitHubIssueTaskPreview
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text("#\(issue.number)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(issue.title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private struct NewProjectSheet: View {
    @Binding var name: String
    @Binding var error: String
    let baseDirectory: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Base directory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(baseDirectory.abbreviatedPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("(change in Settings)")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Project Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { onAdd() } }

            if !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create", action: onAdd)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
