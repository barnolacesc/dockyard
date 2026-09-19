// ABOUTME: Overview shown when a project is selected but no workstream is active.
// ABOUTME: Native Form layout with project info, repo status, and workstream list.

import SwiftUI

struct ProjectRootTerminalView: View {
    let project: Project
    let onClose: () -> Void

    @EnvironmentObject private var surfaceCache: TerminalSurfaceCache

    private var surfaceID: UUID {
        derivedUUID(from: project.id, salt: "project-root-terminal")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text("Project Terminal")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(minWidth: 40, minHeight: 40)
                }
                .buttonStyle(.plain)
                .pressable()
                .accessibilityLabel("Close project terminal")
                .help("Close project terminal")
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 44)
            .background(.bar)

            Divider()

            SingleTerminalView(
                surfaceID: surfaceID,
                workstreamID: project.id,
                workingDirectory: project.directory
            )
        }
        .onAppear {
            surfaceCache.updateOcclusion(visibleSurfaceIDs: [surfaceID])
        }
        .onDisappear {
            surfaceCache.updateOcclusion(visibleSurfaceIDs: [])
        }
        .onReceive(NotificationCenter.default.publisher(for: .terminalTabExited)) { notification in
            guard notification.object as? UUID == surfaceID else { return }
            onClose()
        }
    }
}

struct ProjectOverviewView: View {
    @Binding var project: Project
    let onSelectWorkstream: (UUID) -> Void
    let onRemoveWorkstream: (UUID) -> Void
    let onPurgeWorkstream: (UUID) -> Void
    let onProjectChanged: () -> Void

    @EnvironmentObject var appEnv: AppEnvironment
    @AppStorage("dockyard.workstreamSortOrder") private var workstreamSortOrder: ProjectSortOrder = .recent
    @State private var worktrees: [WorktreeInfo] = []
    @State private var isLoadingWorktrees = false
    @State private var showingPruneConfirm = false
    @State private var showingPruneMergedConfirm = false
    @State private var isPruning = false
    @State private var isPruningMerged = false
    @State private var worktreeFilter: WorktreeFilter = .all
    @State private var showingRepoChanges = false
    @State private var worktreeToDelete: WorktreeInfo?
    @State private var showingDeleteConfirm = false

    @AppStorage("dockyard.defaultTerminal") private var defaultTerminal: String = ""
    @State private var docFiles: [DocFile] = []
    @State private var selectedDoc: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (outside Form to avoid row styling)
            VStack(spacing: 4) {
                TextField("", text: $project.name)
                    .font(.system(size: 22, weight: .bold))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .onChange(of: project.name) { _, _ in onProjectChanged() }

                DirectoryRow(path: project.directory, defaultTerminal: defaultTerminal, githubURL: appEnv.githubURL(for: project.directory))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            Form {
                // MARK: - Repository

                if let info = appEnv.repoInfo(for: project.directory) {
                    Section("Repository") {
                        if info.isRepo {
                            LabeledContent("Branch") {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.caption)
                                    Text(info.branch ?? "unknown")
                                }
                                .foregroundStyle(.secondary)
                            }

                            if let count = info.commitCount {
                                LabeledContent("Commits") {
                                    Text("\(count)")
                                        .tabularNumbers()
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let remote = info.remoteURL {
                                LabeledContent("Remote") {
                                    Text(remote)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            LabeledContent("Status") {
                                if info.isDirty {
                                    Button {
                                        showingRepoChanges = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(DesignColor.statusWarning)
                                                .frame(width: 6, height: 6)
                                            Text(info.modifiedCount == 0
                                                ? String(format: NSLocalizedString(info.untrackedCount == 1 ? "%d untracked file" : "%d untracked files", comment: ""), info.untrackedCount)
                                                : NSLocalizedString("Uncommitted changes", comment: ""))
                                                .foregroundStyle(DesignColor.statusWarning)
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 10))
                                                .foregroundStyle(DesignColor.statusWarning.opacity(0.8))
                                        }
                                        .frame(minHeight: 28)
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showingRepoChanges) {
                                        UncommittedChangesPopover(
                                            path: project.directory,
                                            title: project.name,
                                            onDiscard: { reloadProjectOverview() },
                                            onCleanUntracked: { reloadProjectOverview() }
                                        )
                                    }
                                } else {
                                    Text("Clean")
                                        .foregroundStyle(DesignColor.statusSuccess)
                                }
                            }
                        } else {
                            LabeledContent("Status") {
                                Text("Not a git repository")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // MARK: - GitHub

                if appEnv.ghAvailable, let ghInfo = appEnv.githubRepo(for: project.directory) {
                    Section("GitHub") {
                        LabeledContent("Repository") {
                            Text(ghInfo.name)
                                .foregroundStyle(.secondary)
                        }

                        if let desc = ghInfo.description, !desc.isEmpty {
                            LabeledContent("Description") {
                                Text(desc)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        LabeledContent("Stars") {
                            Text("\(ghInfo.stars)")
                                .tabularNumbers()
                                .foregroundStyle(.secondary)
                        }

                        LabeledContent("Open Issues") {
                            Text("\(ghInfo.openIssues)")
                                .tabularNumbers()
                                .foregroundStyle(.secondary)
                        }

                        let prs = appEnv.githubPRs(for: project.directory)
                        if !prs.isEmpty {
                            LabeledContent("Open PRs") {
                                Text("\(prs.count)")
                                    .tabularNumbers()
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(prs, id: \.number) { pr in
                                LabeledContent {
                                    HStack {
                                        if let url = URL(string: pr.url) {
                                            Link(pr.title, destination: url)
                                                .lineLimit(1)
                                        }
                                        PRChecksBadge(pr: pr, directory: project.directory, compact: true)
                                    }
                                } label: {
                                    if let url = URL(string: pr.url) {
                                        Link(destination: url) {
                                            Text(verbatim: "#\(pr.number)").tabularNumbers().frame(minHeight: 40)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // MARK: - Workstreams

                Section {
                    if project.workstreams.isEmpty {
                        HStack {
                            Spacer()
                            Text("No workstreams yet")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        let sorted = sortedWorkstreams(project.workstreams)
                        ForEach(sorted) { workstream in
                            let branch = appEnv.branchName(for: workstream.worktreePath)
                            let pr = branch.flatMap { appEnv.githubPR(for: project.directory, branch: $0) }
                            WorkstreamRow(
                                workstream: workstream,
                                isPathValid: appEnv.isPathValid(workstream.worktreePath),
                                hasActivePort: appEnv.hasActivePort(workstream.id),
                                taskDescription: appEnv.taskDescription(for: workstream.worktreePath),
                                branchName: branch,
                                prTitle: pr?.title,
                                prNumber: pr?.number,
                                prState: pr?.state,
                                prURL: pr?.url,
                                pullRequest: pr,
                                projectDirectory: project.directory,
                                onSelect: { onSelectWorkstream(workstream.id) },
                                onRemove: { onRemoveWorkstream(workstream.id) },
                                onPurge: { onPurgeWorkstream(workstream.id) }
                            )
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Workstreams")
                        if !project.workstreams.isEmpty {
                            Text("\(project.workstreams.count)")
                                .font(.system(size: 11))
                                .tabularNumbers()
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        if project.workstreams.count > 1 {
                            Picker("", selection: $workstreamSortOrder) {
                                ForEach(ProjectSortOrder.allCases, id: \.self) { order in
                                    Text(order.rawValue).tag(order)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    }
                }

                // MARK: - Worktrees

                if !worktrees.isEmpty || isLoadingWorktrees {
                    Section {
                        if worktrees.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else if worktrees.count > 1 {
                            Picker("", selection: $worktreeFilter) {
                                ForEach(WorktreeFilter.allCases) { filter in
                                    Text(filterLabel(filter)).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical, 4)
                        }

                        ForEach(filteredWorktrees) { wt in
                            let matchingWorkstream = project.workstreams.first { ws in
                                guard let path = ws.worktreePath else { return false }
                                return Self.standardizedPath(path) == Self.standardizedPath(wt.path)
                            }
                            WorktreeInfoRow(
                                worktree: wt,
                                projectDirectory: project.directory,
                                workstreamID: matchingWorkstream?.id,
                                isPullRequestLookupComplete: wt.branch.map {
                                    appEnv.githubPRLookupCompleted(
                                        for: project.directory,
                                        branch: $0
                                    )
                                } ?? false,
                                onSelectWorkstream: onSelectWorkstream,
                                onRemoveWorkstream: onRemoveWorkstream,
                                onPurgeWorkstream: onPurgeWorkstream,
                                onAdopt: { adoptWorktree(wt) },
                                onDelete: {
                                    worktreeToDelete = wt
                                    showingDeleteConfirm = true
                                },
                                onChangesDiscarded: { reloadProjectOverview() }
                            )
                        }

                        if prunableMergedCount > 0 {
                            Button(action: { showingPruneMergedConfirm = true }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.merge")
                                        .font(.system(size: 12))
                                    Text(String(format: NSLocalizedString(prunableMergedCount == 1 ? "Prune %d merged worktree" : "Prune %d merged worktrees", comment: ""), prunableMergedCount))
                                }
                            }
                            .foregroundStyle(DesignColor.statusMerged)
                            .pressable()
                            .disabled(isPruningMerged)
                        }

                        if prunableCleanCount > 0 {
                            Button(action: { showingPruneConfirm = true }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                    Text(String(format: NSLocalizedString(prunableCleanCount == 1 ? "Prune %d clean worktree" : "Prune %d clean worktrees", comment: ""), prunableCleanCount))
                                }
                            }
                            .foregroundStyle(DesignColor.statusError)
                            .pressable()
                            .disabled(isPruning)
                        }
                    } header: {
                        HStack(spacing: 10) {
                            Text("Git Worktrees")
                            if isLoadingWorktrees, !worktrees.isEmpty {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Spacer()
                            if mergedCount > 0 {
                                WorktreeStatusCount(
                                    count: mergedCount,
                                    color: DesignColor.statusMerged,
                                    helpText: NSLocalizedString("Merged", comment: "")
                                )
                            }
                            if dirtyCount > 0 {
                                WorktreeStatusCount(
                                    count: dirtyCount,
                                    color: DesignColor.statusWarning,
                                    helpText: NSLocalizedString("Uncommitted changes", comment: "")
                                )
                            }
                            if aheadCount > 0 {
                                WorktreeStatusCount(
                                    count: aheadCount,
                                    color: DesignColor.statusInfo,
                                    helpText: NSLocalizedString("Commits ahead", comment: "")
                                )
                            }
                            if cleanCount > 0 {
                                WorktreeStatusCount(
                                    count: cleanCount,
                                    color: DesignColor.statusSuccess,
                                    helpText: NSLocalizedString("Clean", comment: "")
                                )
                            }
                            Text("\(worktrees.count)")
                                .font(.caption)
                                .tabularNumbers()
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Worktrees on disk for this repository. Pruning removes clean or merged worktrees that are not associated with a workstream.")
                    }
                }
            }
            .formStyle(.grouped)

            // Markdown content
            if let selected = selectedDoc,
               let doc = docFiles.first(where: { $0.name == selected })
            {
                Divider()
                MarkdownContentView(markdown: doc.content)
                    .id(selected)
            }

            // Doc tabs pinned to bottom
            if !docFiles.isEmpty {
                Divider()
                HStack(spacing: 0) {
                    ForEach(docFiles) { doc in
                        DocTabButton(
                            name: doc.name,
                            isActive: selectedDoc == doc.name,
                            action: { selectedDoc = selectedDoc == doc.name ? nil : doc.name }
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        } // VStack
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadProjectOverview()
        }
        .onChange(of: project.directory) { _, _ in
            worktrees = []
            docFiles = []
            selectedDoc = nil
            reloadProjectOverview()
        }
        .alert("Prune Worktrees", isPresented: $showingPruneConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Prune", role: .destructive) { pruneCleanWorktrees() }
        } message: {
            Text(String(format: NSLocalizedString(prunableCleanCount == 1 ? "Remove %d clean worktree with no uncommitted changes?" : "Remove %d clean worktrees with no uncommitted changes?", comment: ""), prunableCleanCount))
        }
        .alert("Prune Merged Worktrees", isPresented: $showingPruneMergedConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Prune Merged", role: .destructive) { pruneMergedWorktrees() }
        } message: {
            Text(String(format: NSLocalizedString(prunableMergedCount == 1 ? "Remove %d merged worktree and delete its local branch?" : "Remove %d merged worktrees and delete their local branches?", comment: ""), prunableMergedCount))
        }
        .alert(isDeleteWarning ? "Delete Worktree with Changes?" : "Delete Worktree", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { worktreeToDelete = nil }
            Button(isDeleteWarning ? "Force Delete" : "Delete", role: .destructive) {
                if let wt = worktreeToDelete {
                    deleteWorktree(wt)
                }
                worktreeToDelete = nil
            }
        } message: {
            if let wt = worktreeToDelete {
                if wt.isDirty {
                    Text(String(format: NSLocalizedString("Worktree '%@' has uncommitted changes that will be permanently lost.", comment: ""), wt.branch ?? wt.path.components(separatedBy: "/").last ?? "worktree"))
                } else if wt.hasUnpushedCommits {
                    Text(String(format: NSLocalizedString("Worktree '%@' has unpushed commits that will be lost.", comment: ""), wt.branch ?? wt.path.components(separatedBy: "/").last ?? "worktree"))
                } else {
                    Text(String(format: NSLocalizedString("Remove worktree '%@' and delete its local branch?", comment: ""), wt.branch ?? wt.path.components(separatedBy: "/").last ?? "worktree"))
                }
            }
        }
    }

    private var workstreamPaths: Set<String> {
        Set(project.workstreams.compactMap(\.worktreePath).map(Self.standardizedPath))
    }

    private var isDeleteWarning: Bool {
        worktreeToDelete?.isDirty == true || worktreeToDelete?.hasUnpushedCommits == true
    }

    private func isWorktreeMerged(_ wt: WorktreeInfo) -> Bool {
        if wt.isMergedIntoBase { return true }
        if let branch = wt.branch,
           let pr = appEnv.githubPR(for: project.directory, branch: branch),
           pr.state == "MERGED"
        {
            return true
        }
        return false
    }

    private var mergedCount: Int {
        worktrees.filter { !$0.isMain && isWorktreeMerged($0) }.count
    }

    private var dirtyCount: Int {
        worktrees.filter { !$0.isMain && !isWorktreeMerged($0) && $0.isDirty }.count
    }

    private var aheadCount: Int {
        worktrees.filter { !$0.isMain && !isWorktreeMerged($0) && !$0.isDirty && $0.hasBranchCommits }.count
    }

    private var cleanCount: Int {
        worktrees.filter { !$0.isMain && !isWorktreeMerged($0) && !$0.isDirty && !$0.hasBranchCommits }.count
    }

    private var prunableCleanWorktrees: [WorktreeInfo] {
        worktrees.filter { worktree in
            guard !worktree.isMain, !worktree.isDirty, !worktree.hasBranchCommits else { return false }
            return !workstreamPaths.contains(Self.standardizedPath(worktree.path))
        }
    }

    private var prunableCleanPaths: Set<String> {
        Set(prunableCleanWorktrees.map(\.path).map(Self.standardizedPath))
    }

    private var prunableCleanCount: Int {
        prunableCleanWorktrees.count
    }

    private var prunableMergedWorktrees: [WorktreeInfo] {
        worktrees.filter { wt in
            guard !wt.isMain, isWorktreeMerged(wt) else { return false }
            return !workstreamPaths.contains(Self.standardizedPath(wt.path))
        }
    }

    private var prunableMergedPaths: Set<String> {
        Set(prunableMergedWorktrees.map(\.path).map(Self.standardizedPath))
    }

    private var prunableMergedCount: Int {
        prunableMergedWorktrees.count
    }

    private var filteredWorktrees: [WorktreeInfo] {
        let sorted = ProjectOverviewState.triageSorted(worktrees)
        switch worktreeFilter {
        case .all:
            return sorted
        case .workstreams:
            return sorted.filter { wt in
                workstreamPaths.contains(Self.standardizedPath(wt.path))
            }
        case .orphaned:
            return sorted.filter { wt in
                !wt.isMain && !workstreamPaths.contains(Self.standardizedPath(wt.path))
            }
        case .merged:
            return sorted.filter { wt in
                !wt.isMain && isWorktreeMerged(wt)
            }
        }
    }

    private func filterLabel(_ filter: WorktreeFilter) -> String {
        switch filter {
        case .all:
            return String(format: NSLocalizedString("All (%d)", comment: ""), worktrees.count)
        case .workstreams:
            let count = worktrees.filter { workstreamPaths.contains(Self.standardizedPath($0.path)) }.count
            return String(format: NSLocalizedString("Workstreams (%d)", comment: ""), count)
        case .orphaned:
            let count = worktrees.filter { !$0.isMain && !workstreamPaths.contains(Self.standardizedPath($0.path)) }.count
            return String(format: NSLocalizedString("Orphaned (%d)", comment: ""), count)
        case .merged:
            return String(format: NSLocalizedString("Merged (%d)", comment: ""), mergedCount)
        }
    }

    private func deleteWorktree(_ wt: WorktreeInfo) {
        let dir = project.directory
        let path = wt.path
        let branch = wt.branch
        Task.detached {
            GitOperations.deleteWorktreeAndBranch(projectPath: dir, worktreePath: path, branchName: branch)
            await MainActor.run {
                self.refreshWorktrees()
            }
        }
    }

    private func pruneCleanWorktrees() {
        isPruning = true
        let dir = project.directory
        let pathsToPrune = prunableCleanPaths
        Task.detached {
            GitOperations.pruneCleanWorktrees(at: dir, onlyPaths: pathsToPrune)
            await applyPrunedWorktrees(pathsToPrune, loadedFor: dir)
        }
    }

    private func pruneMergedWorktrees() {
        isPruningMerged = true
        let dir = project.directory
        let pathsToPrune = prunableMergedPaths
        Task.detached {
            GitOperations.pruneMergedWorktrees(at: dir, onlyPaths: pathsToPrune)
            await applyPrunedWorktrees(pathsToPrune, loadedFor: dir)
        }
    }

    private func adoptWorktree(_ worktree: WorktreeInfo) {
        let name = worktree.branch ?? worktree.path.components(separatedBy: "/").last ?? "workstream"
        let workstream = Workstream(name: name, worktreePath: worktree.path)
        NotificationCenter.default.post(
            name: .workstreamCreated,
            object: nil,
            userInfo: ["projectID": project.id, "workstream": workstream]
        )
    }

    private func reloadProjectOverview() {
        appEnv.refreshRepoInfo(for: project.directory)
        appEnv.refreshGitHubInfo(for: project.directory)
        refreshWorktrees()
        loadDocFiles()
    }

    private func refreshWorktrees() {
        let dir = project.directory
        isLoadingWorktrees = true
        Task.detached {
            let wts = GitOperations.listWorktreesWithInfo(at: dir)
            await updateWorktrees(wts, loadedFor: dir)
            // Populate PR cache for worktree branches
            let branches = Set(wts.compactMap(\.branch))
            await MainActor.run {
                appEnv.refreshBranchPRs(for: dir, branches: branches)
            }
        }
    }

    private func loadDocFiles() {
        let dir = project.directory
        Task.detached {
            let found = DocFile.loadFrom(directory: dir)
            await updateDocFiles(found, loadedFor: dir)
        }
    }

    private func sortedWorkstreams(_ workstreams: [Workstream]) -> [Workstream] {
        switch workstreamSortOrder {
        case .recent:
            return workstreams.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        case .alphabetical:
            return workstreams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    @MainActor
    private func updateWorktrees(_ worktrees: [WorktreeInfo], loadedFor directory: String) {
        guard let worktrees = ProjectOverviewState.worktreesToApply(
            worktrees,
            loadedFor: directory,
            currentDirectory: project.directory
        ) else { return }
        self.worktrees = worktrees
        isLoadingWorktrees = false
    }

    @MainActor
    private func updateDocFiles(_ docFiles: [DocFile], loadedFor directory: String) {
        guard ProjectOverviewState.matchesProject(loadedFor: directory, currentDirectory: project.directory) else { return }
        self.docFiles = docFiles
    }

    @MainActor
    private func applyPrunedWorktrees(_ prunablePaths: Set<String>, loadedFor directory: String) {
        guard ProjectOverviewState.matchesProject(loadedFor: directory, currentDirectory: project.directory) else {
            isPruning = false
            return
        }
        project.workstreams.removeAll { ws in
            guard let path = ws.worktreePath else { return false }
            return prunablePaths.contains(Self.standardizedPath(path))
        }
        onProjectChanged()
        isPruning = false
        refreshWorktrees()
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

enum WorktreeReviewStatus: Equatable {
    case clean
    case dirty(untrackedOnly: Bool, count: Int)
    case ahead
    case merged(hasUncommitted: Bool, untrackedOnly: Bool, count: Int)
    case unknown
}

enum WorktreeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case workstreams = "Workstreams"
    case orphaned = "Orphaned"
    case merged = "Merged"
    var id: String {
        rawValue
    }
}

enum ProjectOverviewState {
    static func worktreesToApply(
        _ worktrees: [WorktreeInfo],
        loadedFor directory: String,
        currentDirectory: String
    ) -> [WorktreeInfo]? {
        guard matchesProject(loadedFor: directory, currentDirectory: currentDirectory) else {
            return nil
        }
        return worktrees
    }

    static func matchesProject(loadedFor directory: String, currentDirectory: String) -> Bool {
        standardizedPath(directory) == standardizedPath(currentDirectory)
    }

    static func reviewStatus(
        for worktree: WorktreeInfo,
        pullRequestState: String?,
        isPullRequestLookupComplete: Bool
    ) -> WorktreeReviewStatus {
        let isMerged = pullRequestState == "MERGED" || worktree.isMergedIntoBase
        if isMerged {
            return .merged(
                hasUncommitted: worktree.isDirty,
                untrackedOnly: worktree.isDirty && worktree.modifiedCount == 0,
                count: worktree.uncommittedCount
            )
        }
        if worktree.isDirty {
            return .dirty(
                untrackedOnly: worktree.modifiedCount == 0,
                count: worktree.uncommittedCount
            )
        }
        if !worktree.hasBranchCommits {
            return .clean
        }
        return isPullRequestLookupComplete ? .ahead : .unknown
    }

    /// Order worktrees for review: main first, then ones with uncommitted changes,
    /// then ones with commits ahead, then clean ones; alphabetical within each group.
    static func triageSorted(_ worktrees: [WorktreeInfo]) -> [WorktreeInfo] {
        func rank(_ wt: WorktreeInfo) -> Int {
            if wt.isMain { return 0 }
            if wt.isDirty { return 1 }
            if wt.hasBranchCommits { return 2 }
            return 3
        }
        return worktrees.sorted { a, b in
            let ra = rank(a)
            let rb = rank(b)
            if ra != rb { return ra < rb }
            return (a.branch ?? a.path).localizedCaseInsensitiveCompare(b.branch ?? b.path) == .orderedAscending
        }
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

private struct WorktreeStatusCount: View {
    let count: Int
    let color: Color
    let helpText: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.caption)
                .tabularNumbers()
                .foregroundStyle(.secondary)
        }
        .help(helpText)
    }
}

private struct WorktreeInfoRow: View {
    let worktree: WorktreeInfo
    let projectDirectory: String
    let workstreamID: UUID?
    let isPullRequestLookupComplete: Bool
    let onSelectWorkstream: (UUID) -> Void
    let onRemoveWorkstream: (UUID) -> Void
    let onPurgeWorkstream: (UUID) -> Void
    let onAdopt: () -> Void
    let onDelete: () -> Void
    let onChangesDiscarded: () -> Void

    @EnvironmentObject var appEnv: AppEnvironment
    @EnvironmentObject var agentStateStore: AgentStateStore
    @State private var showingChangesPopover = false

    private var pr: GitHubPR? {
        guard let branch = worktree.branch else { return nil }
        return appEnv.githubPR(for: projectDirectory, branch: branch)
    }

    private var reviewStatus: WorktreeReviewStatus {
        ProjectOverviewState.reviewStatus(
            for: worktree,
            pullRequestState: pr?.state,
            isPullRequestLookupComplete: isPullRequestLookupComplete
        )
    }

    var body: some View {
        HStack {
            if let workstreamID {
                ActivityIndicator(
                    state: agentStateStore.agentState(for: workstreamID),
                    isPathValid: appEnv.isPathValid(worktree.path)
                )
                .padding(.top, 4)
                .frame(width: 20, alignment: .top)
            } else {
                Image(systemName: worktree.isMain ? "folder.fill" : "arrow.triangle.branch")
                    .foregroundStyle(worktree.isMain ? DesignColor.statusInfo : .secondary)
                    .frame(width: 20, alignment: .top)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(worktree.branch ?? "detached")
                    .font(.system(.body, design: .monospaced))
                Text(worktree.path.abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if !worktree.isMain {
                    HStack(spacing: 8) {
                        if let pr {
                            let prColor: Color = pr.state == "MERGED" ? DesignColor.statusMerged : DesignColor.statusSuccess
                            Link(destination: URL(string: pr.url)!) {
                                HStack(spacing: 3) {
                                    Image(systemName: pr.state == "MERGED" ? "arrow.triangle.merge" : "arrow.triangle.pull")
                                        .font(.system(size: 10))
                                    Text(verbatim: "#\(pr.number)")
                                        .font(.caption)
                                        .tabularNumbers()
                                }
                                .foregroundStyle(prColor)
                            }
                            PRChecksBadge(pr: pr, directory: projectDirectory, compact: true)
                        }
                        switch reviewStatus {
                        case let .dirty(untrackedOnly, count):
                            Button {
                                showingChangesPopover = true
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(DesignColor.statusWarning)
                                        .frame(width: 6, height: 6)
                                    Text(untrackedOnly
                                        ? String(format: NSLocalizedString(count == 1 ? "%d untracked file" : "%d untracked files", comment: ""), count)
                                        : NSLocalizedString("Uncommitted changes", comment: ""))
                                        .font(.caption)
                                        .foregroundStyle(DesignColor.statusWarning)
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(DesignColor.statusWarning.opacity(0.8))
                                }
                                .frame(minHeight: 28)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showingChangesPopover) {
                                UncommittedChangesPopover(
                                    path: worktree.path,
                                    title: worktree.branch ?? worktree.path.abbreviatedPath,
                                    onDiscard: onChangesDiscarded,
                                    onCleanUntracked: onChangesDiscarded
                                )
                            }
                        case let .merged(hasUncommitted, untrackedOnly, count):
                            HStack(spacing: 6) {
                                if let pr, let url = URL(string: pr.url) {
                                    Link(destination: url) {
                                        Label("Merged", systemImage: "arrow.triangle.merge")
                                            .font(.caption)
                                            .foregroundStyle(DesignColor.statusMerged)
                                            .frame(minHeight: 28)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open on GitHub")
                                } else {
                                    Label("Merged", systemImage: "arrow.triangle.merge")
                                        .font(.caption)
                                        .foregroundStyle(DesignColor.statusMerged)
                                        .frame(minHeight: 28)
                                }

                                if hasUncommitted {
                                    Button {
                                        showingChangesPopover = true
                                    } label: {
                                        HStack(spacing: 3) {
                                            Circle()
                                                .fill(DesignColor.statusWarning)
                                                .frame(width: 5, height: 5)
                                            Text(untrackedOnly
                                                ? String(format: NSLocalizedString(count == 1 ? "%d untracked" : "%d untracked", comment: ""), count)
                                                : NSLocalizedString("Uncommitted", comment: ""))
                                                .font(.caption)
                                                .foregroundStyle(DesignColor.statusWarning)
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 9))
                                                .foregroundStyle(DesignColor.statusWarning.opacity(0.8))
                                        }
                                        .frame(minHeight: 28)
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showingChangesPopover) {
                                        UncommittedChangesPopover(
                                            path: worktree.path,
                                            title: worktree.branch ?? worktree.path.abbreviatedPath,
                                            onDiscard: onChangesDiscarded,
                                            onCleanUntracked: onChangesDiscarded
                                        )
                                    }
                                }
                            }
                        case .ahead:
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 10))
                                Text("Commits ahead")
                                    .font(.caption)
                            }
                            .foregroundStyle(DesignColor.statusInfo)
                        case .clean:
                            Text("Clean")
                                .font(.caption)
                                .foregroundStyle(DesignColor.statusSuccess)
                        case .unknown:
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 10))
                                Text("PR status unavailable")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minHeight: 36, alignment: .leading)
            Spacer()
            if worktree.isMain {
                Text("main")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let workstreamID {
                Button(action: { onSelectWorkstream(workstreamID) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 11))
                        Text("Switch")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
                    .frame(minHeight: 36)
                }
                .pressable()
                .help("Switch to this workstream")
            } else {
                HStack(spacing: 6) {
                    Button(action: onAdopt) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.rectangle.on.folder")
                                .font(.system(size: 12))
                            Text("Open")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
                        .frame(minHeight: 36)
                    }
                    .pressable()
                    .help("Open as workstream in Dockyard")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignColor.statusError)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
                    }
                    .pressable()
                    .help("Delete worktree and branch")
                }
            }
        }
        .hoverHighlight(radius: DesignRadius.md)
        .contextMenu {
            if let workstreamID {
                Button {
                    onSelectWorkstream(workstreamID)
                } label: {
                    Label("Switch to Workstream", systemImage: "arrow.right.circle")
                }
            } else if !worktree.isMain {
                Button(action: onAdopt) {
                    Label("Open as Workstream", systemImage: "plus.rectangle.on.folder")
                }
            }
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Button {
                openDirectoryInTerminal(worktree.path)
            } label: {
                Label("Open in External Terminal", systemImage: "terminal")
            }
            if let pr, let url = URL(string: pr.url) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("View on GitHub", systemImage: "arrow.up.right.square")
                }
            }
            if let branch = worktree.branch {
                Button {
                    copyTextToPasteboard(branch)
                } label: {
                    Label("Copy branch name", systemImage: "arrow.triangle.branch")
                }
            }
            Button {
                copyTextToPasteboard(worktree.path)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            if worktree.isDirty {
                Divider()
                Button {
                    showingChangesPopover = true
                } label: {
                    Label("View Uncommitted Changes…", systemImage: "info.circle")
                }
            }
            if !worktree.isMain {
                Divider()
                if let workstreamID {
                    Button(action: { onRemoveWorkstream(workstreamID) }) {
                        Label("Remove Workstream", systemImage: "xmark")
                    }
                    Button(role: .destructive) {
                        onPurgeWorkstream(workstreamID)
                    } label: {
                        Label("Purge Workstream…", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Worktree…", systemImage: "trash")
                    }
                }
            }
        }
    }
}

private struct WorkstreamRow: View {
    let workstream: Workstream
    var isPathValid: Bool = true
    var hasActivePort: Bool = false
    var taskDescription: String?
    var branchName: String?
    var prTitle: String?
    var prNumber: Int?
    var prState: String?
    var prURL: String?
    var pullRequest: GitHubPR?
    var projectDirectory: String = ""
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onPurge: () -> Void

    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// The most descriptive label we have for this workstream.
    private var headline: String {
        if let prTitle { return prTitle }
        if let taskDescription { return taskDescription }
        return workstream.name
    }

    /// Whether the headline came from a description/PR (true) or is just the generated name (false).
    private var hasRichHeadline: Bool {
        prTitle != nil || taskDescription != nil
    }

    /// Secondary line: branch name when we have a rich headline, otherwise nil.
    private var subtitle: String? {
        guard isPathValid else { return nil }
        if hasRichHeadline {
            return branchName ?? workstream.name
        }
        if let branchName, branchName != workstream.name {
            return branchName
        }
        return nil
    }

    var body: some View {
        Group {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if !isPathValid {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(DesignColor.statusWarning)
                                .font(.system(size: 11))
                        }
                        Text(headline)
                            .font(.system(hasRichHeadline ? .body : .body, design: hasRichHeadline ? .default : .monospaced))
                            .strikethrough(!isPathValid)
                            .foregroundStyle(isPathValid ? .primary : .secondary)
                            .lineLimit(1)
                        if hasActivePort {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(DesignColor.statusSuccess)
                        }
                        if let prNumber, let prState {
                            PRBadge(number: prNumber, state: prState, url: prURL)
                        }
                        if let pullRequest {
                            PRChecksBadge(pr: pullRequest, directory: projectDirectory)
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 36, alignment: .leading)
                Spacer()
                Text(Self.relativeFormatter.localizedString(for: workstream.lastAccessedAt, relativeTo: Date()))
                    .font(.system(size: 11))
                    .tabularNumbers()
                    .foregroundStyle(.secondary)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
                }
                .pressable()
                .opacity(isHovering ? 1 : 0)
            }
        }
        .onTapGesture(perform: onSelect)
        .accessibilityAction { onSelect() }
        .hoverHighlight(radius: DesignRadius.md)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if let worktreePath = workstream.worktreePath {
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
                Divider()
            }
            if let branchName {
                Button {
                    copyTextToPasteboard(branchName)
                } label: {
                    Label("Copy branch name", systemImage: "arrow.triangle.branch")
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
}

private struct PRBadge: View {
    let number: Int
    let state: String
    var url: String?

    private var color: Color {
        switch state {
        case "MERGED": return DesignColor.statusMerged
        case "CLOSED": return DesignColor.statusError
        default: return DesignColor.statusSuccess
        }
    }

    private var icon: String {
        switch state {
        case "MERGED": return "arrow.triangle.merge"
        default: return "arrow.triangle.pull"
        }
    }

    var body: some View {
        let label = HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(verbatim: "#\(number)")
                .font(.system(size: 11))
                .tabularNumbers()
        }
        .foregroundStyle(color)

        if let url, let dest = URL(string: url) {
            Link(destination: dest) { label }
        } else {
            label
        }
    }
}
