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
    case .settings, .help:
        break
    }
    return expanded
}

extension Notification.Name {
    static let addProject = Notification.Name("dockyard.addProject")
    static let addNew = Notification.Name("dockyard.addNew")
}

struct ProjectSidebar: View {
    @Binding var projects: [Project]
    @Binding var selection: SidebarSelection?
    let onProjectsChanged: () -> Void

    @StateObject private var appUpdater = AppUpdater()

    @State private var showingNewProjectName = false
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
    @AppStorage("dockyard.showRecent") private var showRecent: Bool = true
    @AppStorage(SidebarMode.storageKey) private var sidebarModeRaw = SidebarMode.expanded.rawValue
    @AppStorage(SidebarMode.lastVisibleStorageKey) private var lastVisibleSidebarModeRaw = SidebarMode.expanded.rawValue

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
        return projects.sorted { $0.lastAccessedAt > $1.lastAccessedAt }.map(\.id)
    }

    private func rebuildIndices() {
        cachedProjectIndex = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($1.id, $0) })
        var wsIndex: [UUID: (Int, Int)] = [:]
        var sortedWS: [UUID: [UUID]] = [:]
        for (pi, project) in projects.enumerated() {
            for (wi, ws) in project.workstreams.enumerated() {
                wsIndex[ws.id] = (pi, wi)
            }
            sortedWS[project.id] = project.workstreams
                .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
                .map(\.id)
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
            withAnimation {
                scrollProxy.scrollTo(selected, anchor: .center)
            }
        }
    }

    private func handleTerminalActivity(for workstreamID: UUID) {
        guard let (pi, wi) = cachedWorkstreamIndex[workstreamID] else { return }
        let now = Date()
        projects[pi].lastAccessedAt = now
        projects[pi].workstreams[wi].lastAccessedAt = now
        onProjectsChanged()
        cachedSortedIDs = recomputeSortedIDs()
        cachedSortedWorkstreamIDs[projects[pi].id] = projects[pi].workstreams
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
            .map(\.id)
    }

    private func projectRows() -> some View {
        ForEach(cachedSortedIDs, id: \.self) { projectID in
            let projectBind = projectBinding(for: projectID)
            let project = projectBind.wrappedValue
            let hasChildren = !project.workstreams.isEmpty

            ProjectHeaderRow(
                project: project,
                isExpanded: expandedProjects.contains(project.id),
                onToggle: hasChildren ? {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expandedProjects.contains(project.id) {
                            expandedProjects.remove(project.id)
                        } else {
                            expandedProjects.insert(project.id)
                        }
                    }
                } : nil,
                isGitRepo: appEnv.isGitRepo(project.directory),
                githubURL: appEnv.githubURL(for: project.directory),
                onAdd: { logger.warning("[Dockyard] onAdd button tapped for project \(project.name, privacy: .public)"); addWorkstream(for: project.id) },
                onAddWithPermissions: { addWorkstream(for: project.id, bypassPermissions: true) },
                onAddWithoutPermissions: { addWorkstream(for: project.id, bypassPermissions: false) },
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
                        let isPathValid = appEnv.isPathValid(workstream.worktreePath)
                        let statusStyle = WorkstreamStatusStyle(agentState: agentState, isPathValid: isPathValid)
                        let branch = appEnv.branchName(for: workstream.worktreePath)
                        let pr = branch.flatMap { appEnv.githubPR(for: project.directory, branch: $0) }
                        WorkstreamRow(
                            name: workstream.name,
                            branchName: branch,
                            worktreePath: workstream.worktreePath,
                            agentState: agentState,
                            isPathValid: isPathValid,
                            isSelected: selection == .workstream(workstream.id),
                            hasActivePort: appEnv.hasActivePort(workstream.id),
                            githubURL: appEnv.githubURL(for: project.directory, branch: branch),
                            taskDescription: appEnv.taskDescription(for: workstream.worktreePath),
                            prTitle: pr?.title,
                            prNumber: pr?.number,
                            prState: pr?.state,
                            uncommittedCount: workstream.worktreePath.map { appEnv.worktreeState(for: $0).uncommittedCount } ?? 0,
                            onRemove: { workstreamToRemove = workstream.id },
                            onPurge: { confirmPurge(workstream) },
                            onRename: {
                                workstreamToRename = workstream.id
                                newWorkstreamName = workstream.name
                            }
                        )
                        .tag(SidebarSelection.workstream(workstream.id))
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
            }
        }
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
                onToggle: { withAnimation(.easeInOut(duration: 0.15)) { showOpenPRs.toggle() } }
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

    /// Collapsible "Recent" section with the most recently touched workstreams for fast
    /// switching, independent of project grouping. Rendered outside the scrolling List and
    /// pinned above the bottom bar, so Recent stays put and is visually separated from the
    /// live project tree.
    @ViewBuilder
    private var pinnedRecentSection: some View {
        let recents = recentWorkstreams(limit: 4)
        if recents.count > 1 {
            VStack(spacing: 0) {
                Divider()
                SidebarSectionHeader(
                    title: NSLocalizedString("Recent", comment: "Sidebar recent workstreams section"),
                    systemImage: "clock",
                    count: nil,
                    isExpanded: showRecent,
                    onToggle: { withAnimation(.easeInOut(duration: 0.15)) { showRecent.toggle() } }
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)
                if showRecent {
                    ForEach(recents, id: \.workstream.id) { entry in
                        RecentRow(
                            name: entry.workstream.name,
                            projectName: entry.project.name,
                            onSelect: { selection = .workstream(entry.workstream.id) }
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }

    /// Workstreams (with a usable worktree path) across all projects, most recently
    /// accessed first, capped at `limit`.
    private func recentWorkstreams(limit: Int) -> [(project: Project, workstream: Workstream)] {
        var all: [(project: Project, workstream: Workstream)] = []
        for project in projects {
            for ws in project.workstreams where ws.worktreePath != nil {
                all.append((project: project, workstream: ws))
            }
        }
        return Array(
            all.sorted { $0.workstream.lastAccessedAt > $1.workstream.lastAccessedAt }.prefix(limit)
        )
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            if !projects.isEmpty {
                SidebarStatusStrip(
                    projectCount: projects.count,
                    workstreamCount: totalWorkstreamCount(),
                    openPRCount: appEnv.openPullRequests(projects: projects).count,
                    waitingCount: waitingAgentCount
                )
                Divider()
                    .padding(.horizontal, 8)
            }
            HStack(alignment: .center, spacing: 6) {
                Text(AppConstants.displayVersion)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                
                if appUpdater.isChecking {
                    ProgressView()
                        .controlSize(.mini)
                } else if appUpdater.commitsAhead > 0 {
                    Button(action: {
                        appUpdater.applyUpdate()
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Update (\(appUpdater.commitsAhead))")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Pull latest changes from main and rebuild")
                } else {
                    Button(action: {
                        appUpdater.checkForUpdates()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Check for updates")
                }
            }
            .padding(.bottom, 4)

            // Credit
            VStack(spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        Text("from ")
                            .foregroundStyle(.tertiary)
                        Link("alltunerlabs", destination: URL(string: "https://davidpoblador.com/")!)
                            .foregroundStyle(.secondary)
                        Text(", tuned by ")
                            .foregroundStyle(.tertiary)
                        Link("barnolacesc", destination: URL(string: "https://github.com/barnolacesc")!)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        HStack(spacing: 0) {
                            Text("from ")
                                .foregroundStyle(.tertiary)
                            Link("alltunerlabs", destination: URL(string: "https://davidpoblador.com/")!)
                                .foregroundStyle(.secondary)
                            Text(",")
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 0) {
                            Text("tuned by ")
                                .foregroundStyle(.tertiary)
                            Link("barnolacesc", destination: URL(string: "https://github.com/barnolacesc")!)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .font(.system(size: 10))
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            HStack {
                Menu {
                    Button("Add Existing Directory…") { openDirectoryPicker() }
                    Button("Create New Project…") { presentNewProjectSheet() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Add project")
                Spacer()
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
            .alert("Update Available", isPresented: $appUpdater.shouldPromptUpdate) {
                Button("Update & Relaunch") { appUpdater.applyUpdate() }
                Button("Later", role: .cancel) {}
            } message: {
                Text("A new version of Dockyard is ready. It will rebuild and relaunch automatically.")
            }
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
                    addWorkstream(for: project.id)
                } else if case let .project(pid) = selection {
                    addWorkstream(for: pid)
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
                onCreateNewProject: { presentNewProjectSheet() }
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
                            .frame(width: 28, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("Collapse sidebar", comment: "Expanded sidebar collapse button tooltip"))
                    .accessibilityLabel("Collapse sidebar")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)

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

                // Recent is pinned to the bottom (separated from the live project tree)
                // so it stays reachable without scrolling.
                pinnedRecentSection

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
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Workstream management

    @AppStorage("dockyard.bypassPermissions") private var defaultBypass: Bool = false
    @AppStorage("dockyard.symlinkEnv") private var symlinkEnv: Bool = true

    private func addWorkstream(for projectID: UUID, bypassPermissions: Bool? = nil) {
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
        let name = NameGenerator.generate(avoiding: existingNames)
        logger.warning("[Dockyard] addWorkstream: generated name=\(name, privacy: .public)")

        let bypass = bypassPermissions ?? defaultBypass
        let workstream = Workstream(name: name, worktreePath: nil, bypassPermissions: bypass)
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
                symlinkEnv: symlink
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

    private var sponsorURL: URL {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let path = lang == "en" ? "/sponsor" : "/\(lang)/sponsor"
        return URL(string: "https://francesc.barnola.net\(path)")!
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
    let isExpanded: Bool
    let onToggle: (() -> Void)?
    let isGitRepo: Bool
    var githubURL: URL?
    let onAdd: () -> Void
    let onAddWithPermissions: () -> Void
    let onAddWithoutPermissions: () -> Void
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
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.borderless)
                    .onHover { isChevronHovering = $0 }
                    .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
                    .accessibilityValue(isExpanded ? "expanded" : "collapsed")
                } else {
                    Color.clear
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))

                    if !project.workstreams.isEmpty {
                        Text("\(project.workstreams.count)")
                            .font(.system(size: 9, weight: .medium))
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
                                Label("New workstream (full permissions)", systemImage: "lock.open")
                            }
                            Button(action: onAddWithoutPermissions) {
                                Label("New workstream (with prompts)", systemImage: "lock.shield")
                            }
                        }
                }
                SidebarIconButton(icon: "trash", action: onDelete)
                    .accessibilityLabel("Remove project")
            }
            .opacity(isHovering ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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
        }
    }
}

enum WorkstreamStatusColor: Equatable {
    case primary
    case secondary
    case tertiary
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
        case .green:
            return AnyShapeStyle(Color.green.opacity(opacity))
        case .blue:
            return AnyShapeStyle(Color.blue.opacity(opacity))
        case .orange:
            return AnyShapeStyle(Color.orange.opacity(opacity))
        }
    }

    func tintColor(opacity: Double = 1) -> Color? {
        switch self {
        case .primary, .secondary, .tertiary:
            return nil
        case .green:
            return Color.green.opacity(opacity)
        case .blue:
            return Color.blue.opacity(opacity)
        case .orange:
            return Color.orange.opacity(opacity)
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
            rowTintColor = .blue
            rowTintOpacity = 0.10
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

private struct WorkstreamRowBackground: View {
    let statusStyle: WorkstreamStatusStyle

    var body: some View {
        Group {
            if let rowTintColor = statusStyle.rowTintColor,
               let tintColor = rowTintColor.tintColor(opacity: statusStyle.rowTintOpacity)
            {
                tintColor
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
    var isPathValid: Bool = false
    var isSelected: Bool = false
    var hasActivePort: Bool = false
    var githubURL: URL?
    var taskDescription: String?
    var prTitle: String?
    var prNumber: Int?
    var prState: String?
    var uncommittedCount: Int = 0
    let onRemove: () -> Void
    let onPurge: () -> Void
    var onRename: (() -> Void)? = nil

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

    private var statusStyle: WorkstreamStatusStyle {
        WorkstreamStatusStyle(agentState: agentState, isPathValid: isPathValid)
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            rowContent
                .padding(.leading, isSelected ? 6 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(taskDescription ?? "")
        .onHover { isHovering = $0 }
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

    private var subtitleStyle: AnyShapeStyle {
        if statusStyle.labelColor == .blue {
            return statusStyle.subtitleStyle
        }
        if prState == "MERGED" {
            return AnyShapeStyle(.purple)
        }
        return statusStyle.subtitleStyle
    }

    private var rowContent: some View {
        HStack(spacing: 4) {
            ActivityIndicator(state: agentState, isPathValid: isPathValid)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(headline)
                        .font(.system(size: 12))
                        .strikethrough(!isPathValid)
                        .foregroundStyle(statusStyle.labelStyle)
                        .lineLimit(1)
                    if hasActivePort {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.green)
                    }
                }
                if subtitle != nil || dirtyCount > 0 {
                    HStack(spacing: 3) {
                        if prState == "MERGED" {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.system(size: 8))
                                .foregroundStyle(.purple)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .lineLimit(1)
                        }
                        if dirtyCount > 0 {
                            Text("±\(dirtyCount)")
                                .foregroundStyle(.secondary)
                                .help(NSLocalizedString("Uncommitted changes", comment: ""))
                        }
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(subtitleStyle)
                }
            }

            Spacer()

            SidebarIconButton(icon: "xmark", action: onRemove)
                .accessibilityLabel("Remove workstream")
                .opacity(isHovering ? 1 : 0)
        }
    }
}

struct ActivityIndicator: View {
    let state: AgentState?
    let isPathValid: Bool

    @State private var isPulsing = false

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
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
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

/// Collapsible header row for an auxiliary sidebar section (Open PRs, Recent).
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
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
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
            Spacer()
            SidebarIconButton(icon: "arrow.up.right.square", action: onOpenURL)
                .opacity(isHovering ? 1 : 0)
        }
        .padding(.leading, 16)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .help(item.pr.title)
    }
}

/// A single "Recent" workstream row: click to select it.
private struct RecentRow: View {
    let name: String
    let projectName: String
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)
            Text(projectName)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.borderless)
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
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
