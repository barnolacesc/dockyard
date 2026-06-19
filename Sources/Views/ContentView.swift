// ABOUTME: Main application view composing the sidebar and terminal content area.
// ABOUTME: Uses NavigationSplitView for the sidebar/detail pattern.

import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "dockyard", category: "content-view")

extension Notification.Name {
    static let workstreamCreated = Notification.Name("dockyard.workstreamCreated")
    static let workstreamWorktreeReady = Notification.Name("dockyard.workstreamWorktreeReady")
    static let workstreamCreationFailed = Notification.Name("dockyard.workstreamCreationFailed")
    static let projectCreated = Notification.Name("dockyard.projectCreated")
    static let purgeWorkstream = Notification.Name("dockyard.purgeWorkstream")
    static let worktreeHeadChanged = Notification.Name("dockyard.worktreeHeadChanged")
}

final class ProjectList: ObservableObject {
    @Published var items: [Project]

    init() {
        items = SidebarManualOrderMigration.seedIfNeeded()
    }
}

enum SidebarManualOrderMigration {
    static let seededKey = "dockyard.sidebarManualOrderSeeded"

    static func seedIfNeeded(defaults: UserDefaults = .standard) -> [Project] {
        guard !defaults.bool(forKey: seededKey) else {
            return ProjectStore.load(defaults: defaults)
        }

        var projects = ProjectStore.load(defaults: defaults)
        seedManualOrder(&projects)
        ProjectStore.save(projects, defaults: defaults)
        defaults.set(true, forKey: seededKey)
        return projects
    }

    static func seedManualOrder(_ projects: inout [Project]) {
        projects = projects.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        for index in projects.indices {
            projects[index].workstreams = projects[index].workstreams.sorted {
                $0.lastAccessedAt > $1.lastAccessedAt
            }
        }
    }
}

func workstreamHasUsablePath(_ workstream: Workstream, pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
    guard let worktreePath = workstream.worktreePath else { return false }
    return pathExists(worktreePath)
}

func renderableWorkstreamID(
    in project: Project,
    selectedWorkstreamID: UUID?,
    pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> UUID? {
    guard let selectedWorkstreamID else { return nil }
    return project.workstreams.contains {
        $0.id == selectedWorkstreamID && workstreamHasUsablePath($0, pathExists: pathExists)
    } ? selectedWorkstreamID : nil
}

func cycledWorkstreamID(
    in project: Project,
    selectedWorkstreamID: UUID?,
    direction: Int,
    pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> UUID? {
    let workstreams = project.workstreams
        .filter { workstreamHasUsablePath($0, pathExists: pathExists) }
    guard !workstreams.isEmpty else { return nil }
    guard let selectedWorkstreamID,
          let currentIndex = workstreams.firstIndex(where: { $0.id == selectedWorkstreamID })
    else {
        return direction > 0 ? workstreams.first?.id : workstreams.last?.id
    }
    let next = (currentIndex + direction + workstreams.count) % workstreams.count
    return workstreams[next].id
}

func cycledGlobalWorkstreamID(
    in projects: [Project],
    selectedWorkstreamID: UUID?,
    direction: Int,
    pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> UUID? {
    let workstreams = projects.flatMap(\.workstreams)
        .filter { workstreamHasUsablePath($0, pathExists: pathExists) }
    guard !workstreams.isEmpty else { return nil }
    guard let selectedWorkstreamID,
          let currentIndex = workstreams.firstIndex(where: { $0.id == selectedWorkstreamID })
    else {
        return direction > 0 ? workstreams.first?.id : workstreams.last?.id
    }
    let next = (currentIndex + direction + workstreams.count) % workstreams.count
    return workstreams[next].id
}

func cycledProjectID(in projects: [Project], selectedProjectID: UUID?, direction: Int) -> UUID? {
    guard !projects.isEmpty else { return nil }
    guard let selectedProjectID,
          let currentIndex = projects.firstIndex(where: { $0.id == selectedProjectID })
    else {
        return direction > 0 ? projects.first?.id : projects.last?.id
    }
    let next = (currentIndex + direction + projects.count) % projects.count
    return projects[next].id
}

func commandKeyNotification(charactersIgnoringModifiers chars: String?, modifierFlags: NSEvent.ModifierFlags) -> Notification.Name? {
    let flags = modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
    let hasCommand = flags.contains(.command)
    let hasShift = flags.contains(.shift)
    let hasOption = flags.contains(.option)
    let hasControl = flags.contains(.control)

    guard hasCommand, !hasControl, !hasOption, let chars else { return nil }

    switch (chars, hasShift) {
    case ("[", false): return .prevWorkstream
    case ("]", false): return .nextWorkstream
    case ("[", true): return .prevTab
    case ("]", true): return .nextTab
    case ("w", false): return .closeTerminal
    default: return nil
    }
}

func commandKeyNotification(event: NSEvent) -> Notification.Name? {
    if let name = commandKeyNotification(charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifierFlags: event.modifierFlags) {
        return name
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
    let hasCommand = flags.contains(.command)
    let hasShift = flags.contains(.shift)
    let hasOption = flags.contains(.option)
    let hasControl = flags.contains(.control)

    guard hasCommand, !hasControl, !hasOption else { return nil }

    // Use keycodes for arrows to be reliable
    switch (event.keyCode, hasShift) {
    case (125, false): return .nextProject // Down arrow
    case (126, false): return .prevProject // Up arrow
    default: return nil
    }
}

struct ContentView: View {
    @StateObject private var projectList = ProjectList()
    @State private var selection: SidebarSelection? = SidebarSelection.loadSaved() ?? ContentView.initialSelection()
    @State private var selectionBeforeSettings: SidebarSelection?

    private var projects: [Project] {
        get { projectList.items }
        nonmutating set { projectList.items = newValue }
    }

    @StateObject private var surfaceCache = TerminalSurfaceCache()
    @StateObject private var appEnvironment = AppEnvironment()
    @StateObject private var activityTracker = WorkstreamActivityTracker()
    @StateObject private var agentStateStore = AgentStateStore.shared
    @StateObject private var claudeUsageStore = ClaudeUsageStore.shared
    @StateObject private var codexUsageStore = CodexUsageStore.shared
    @State private var saveWork: DispatchWorkItem?
    @State private var workstreamToRemove: UUID?
    @State private var workstreamToPurge: UUID?
    @State private var purgeWarningMessage: String?
    @State private var removedProjectNames: [String] = []
    @State private var keyMonitorInstalled = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedUsageProvider: UsageMeterProvider = .claude
    @State private var previousPreferredUsageProvider: UsageMeterProvider?
    @AppStorage("dockyard.codingCLI") private var codingCLIRaw: String = ""
    @AppStorage(SidebarMode.storageKey) private var sidebarModeRaw = SidebarMode.expanded.rawValue
    @AppStorage(SidebarMode.lastVisibleStorageKey) private var lastVisibleSidebarModeRaw = SidebarMode.expanded.rawValue

    /// Fires when a worktree's git HEAD changes (e.g. `git branch -m`) so the sidebar can
    /// resync the workstream name instantly instead of waiting for the 15s poll.
    @State private var headWatcher = WorktreeHeadWatcher { path in
        NotificationCenter.default.post(name: .worktreeHeadChanged, object: path)
    }

    private static func initialSelection() -> SidebarSelection? {
        let projects = ProjectStore.load()
        guard let mostRecent = projects.max(by: { $0.lastAccessedAt < $1.lastAccessedAt }) else { return nil }
        return .project(mostRecent.id)
    }

    private var sidebarMode: SidebarMode {
        SidebarMode(rawValue: sidebarModeRaw) ?? .expanded
    }

    private var lastVisibleSidebarMode: SidebarMode {
        let mode = SidebarMode(rawValue: lastVisibleSidebarModeRaw) ?? .expanded
        return mode.isVisible ? mode : .expanded
    }

    private var activeProject: Project? {
        guard let selection else {
            logger.warning("[Dockyard] activeProject: selection is nil")
            return nil
        }
        switch selection {
        case let .project(id):
            let found = projects.first(where: { $0.id == id })
            if found == nil { logger.warning("[Dockyard] activeProject: project \(id, privacy: .public) not found in \(projects.count, privacy: .public) projects") }
            return found
        case let .workstream(wsID):
            let found = projects.first(where: { $0.workstreams.contains(where: { $0.id == wsID }) })
            if found == nil { logger.warning("[Dockyard] activeProject: workstream \(wsID, privacy: .public) not found in any project") }
            return found
        case .settings, .help:
            return nil
        }
    }

    private var activeWorkstream: Workstream? {
        guard let wsID = selection?.workstreamID,
              let project = activeProject else { return nil }
        return project.workstreams.first(where: { $0.id == wsID })
    }

    private var activeCodingCLI: CodingCLI? {
        guard let activeWorkstream else { return nil }
        let storedValue = effectiveCodingCLIRaw(workstream: activeWorkstream.codingCLI, global: codingCLIRaw)
        return appEnvironment.toolStatus.resolvedCodingCLI(storedValue: storedValue)
    }

    private var preferredUsageProvider: UsageMeterProvider? {
        activeCodingCLI.flatMap(UsageMeterProvider.preferred(for:))
    }

    private var availableUsageProviders: [UsageMeterProvider] {
        var providers: [UsageMeterProvider] = []
        if appEnvironment.toolStatus.claude.isInstalled || claudeUsageStore.hasAnyData {
            providers.append(.claude)
        }
        if appEnvironment.toolStatus.codex.isInstalled || codexUsageStore.hasAnyData {
            providers.append(.codex)
        }
        return providers.isEmpty ? [.claude] : providers
    }

    @ViewBuilder
    private var detailView: some View {
        if selection == .settings {
            SettingsView()
                .navigationTitle("Settings")
                .navigationSubtitle(AppConstants.appName)
        } else if selection == .help {
            HelpView()
                .navigationTitle("Help")
                .navigationSubtitle(AppConstants.appName)
        } else if let workstream = activeWorkstream, let project = activeProject {
            if let workstreamID = renderableWorkstreamID(in: project, selectedWorkstreamID: workstream.id) {
                let scriptConfig = ScriptConfig.load(from: workstream.workingDirectory(projectDirectory: project.directory), fallbackDirectory: project.directory)
                let initialTabState = startupWorkspaceTabState(
                    snapshot: surfaceCache.restoreTabSnapshot(for: workstreamID),
                    persistedSnapshot: WorkspaceTabSnapshotStore.load(for: workstreamID)
                )
                let codingCLIBinding = Binding<String?>(
                    get: {
                        guard let currentProjectIndex = projectList.items.firstIndex(where: { $0.id == project.id }),
                              let currentWorkstreamIndex = projectList.items[currentProjectIndex].workstreams.firstIndex(where: { $0.id == workstreamID })
                        else {
                            return nil
                        }
                        return projectList.items[currentProjectIndex].workstreams[currentWorkstreamIndex].codingCLI
                    },
                    set: { newValue in
                        guard let currentProjectIndex = projectList.items.firstIndex(where: { $0.id == project.id }),
                              let currentWorkstreamIndex = projectList.items[currentProjectIndex].workstreams.firstIndex(where: { $0.id == workstreamID })
                        else {
                            return
                        }
                        projectList.items[currentProjectIndex].workstreams[currentWorkstreamIndex].codingCLI = newValue
                    }
                )
                let bypassPermissionsBinding = Binding<Bool>(
                    get: {
                        guard let currentProjectIndex = projectList.items.firstIndex(where: { $0.id == project.id }),
                              let currentWorkstreamIndex = projectList.items[currentProjectIndex].workstreams.firstIndex(where: { $0.id == workstreamID })
                        else {
                            return false
                        }
                        return projectList.items[currentProjectIndex].workstreams[currentWorkstreamIndex].bypassPermissions
                    },
                    set: { newValue in
                        guard let currentProjectIndex = projectList.items.firstIndex(where: { $0.id == project.id }),
                              let currentWorkstreamIndex = projectList.items[currentProjectIndex].workstreams.firstIndex(where: { $0.id == workstreamID })
                        else {
                            return
                        }
                        projectList.items[currentProjectIndex].workstreams[currentWorkstreamIndex].bypassPermissions = newValue
                    }
                )
                TerminalContainerView(
                    workstreamID: workstreamID,
                    workingDirectory: workstream.workingDirectory(projectDirectory: project.directory),
                    projectDirectory: project.directory,
                    projectName: project.name,
                    workstreamName: workstream.name,
                    bypassPermissions: bypassPermissionsBinding,
                    workstreamCodingCLI: codingCLIBinding,
                    isActive: true,
                    scriptConfig: scriptConfig,
                    initialTabState: initialTabState
                )
                .id(workstreamID)
                .navigationTitle(appEnvironment.taskDescription(for: workstream.worktreePath) ?? workstream.name)
                .navigationSubtitle(workstreamSubtitle(project: project, workstream: workstream))
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Preparing workstream...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(appEnvironment.taskDescription(for: workstream.worktreePath) ?? workstream.name)
                .navigationSubtitle(workstreamSubtitle(project: project, workstream: workstream))
            }
        } else if let project = activeProject,
                  let projectIndex = projects.firstIndex(where: { $0.id == project.id })
        {
            ProjectOverviewView(
                project: $projectList.items[projectIndex],
                onSelectWorkstream: { wsID in selection = .workstream(wsID) },
                onRemoveWorkstream: { wsID in workstreamToRemove = wsID },
                onPurgeWorkstream: { wsID in confirmPurge(wsID) },
                onProjectChanged: { ProjectStore.save(projects) }
            )
            .navigationTitle(project.name)
            .navigationSubtitle(AppConstants.appName)
        } else {
            OnboardingView(toolStatus: appEnvironment.toolStatus, isDetecting: appEnvironment.isDetecting)
                .navigationTitle(AppConstants.appName)
        }
    }

    var body: some View {
        navigationView
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                toggleSidebarVisibility()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarWidth)) { _ in
                toggleSidebarWidth()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openHelp)) { _ in
                if selection == .help {
                    selection = selectionBeforeSettings
                } else {
                    selectionBeforeSettings = selection
                    selection = .help
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                if selection == .settings {
                    selection = selectionBeforeSettings
                } else {
                    selection = .settings
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearProjects)) { _ in
                for project in projects {
                    for ws in project.workstreams {
                        surfaceCache.removeWorkstreamSurfaces(for: ws.id)
                    }
                }
                projects.removeAll()
                selectionBeforeSettings = nil
                selection = .settings
                ProjectStore.save([])
            }
            .onReceive(NotificationCenter.default.publisher(for: .openExternalTerminal)) { _ in
                openExternalTerminal()
            }
            .onChange(of: projectList.items) { _, newValue in
                // Debounce saves to avoid rapid I/O from activity updates
                saveWork?.cancel()
                let work = DispatchWorkItem { ProjectStore.save(newValue) }
                saveWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                syncSelectedUsageProvider()
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
                "Projects Not Found",
                isPresented: Binding(
                    get: { !removedProjectNames.isEmpty },
                    set: { if !$0 { removedProjectNames = [] } }
                )
            ) {
                Button("OK") { removedProjectNames = [] }
            } message: {
                Text(String(format: NSLocalizedString("The following projects were removed because their directories no longer exist on disk: %@", comment: ""), removedProjectNames.joined(separator: ", ")))
            }
    }

    private var navigationView: some View {
        navigationViewBase
            .onChange(of: appEnvironment.missingProjectIDs) { _, missing in
                guard !missing.isEmpty else { return }
                logger.warning("[Dockyard] missingProjectIDs changed: \(missing.count, privacy: .public) missing, \(projects.count, privacy: .public) total projects")
                let names = projects.filter { missing.contains($0.id) }.map(\.name)
                logger.warning("[Dockyard] removing projects: \(names, privacy: .public)")
                for id in missing {
                    if let project = projects.first(where: { $0.id == id }) {
                        for ws in project.workstreams {
                            surfaceCache.removeWorkstreamSurfaces(for: ws.id)
                        }
                    }
                }
                projects.removeAll { missing.contains($0.id) }
                if let sel = selection, case let .project(pid) = sel, missing.contains(pid) {
                    selection = nil
                }
                if let sel = selection, case .workstream = sel, activeProject == nil {
                    selection = nil
                }
                ProjectStore.save(projects)
                removedProjectNames = names
            }
            .onChange(of: selection) { oldValue, newValue in
                logger.warning("[Dockyard] selection changed: \(String(describing: oldValue), privacy: .public) -> \(String(describing: newValue), privacy: .public)")
                if newValue == .settings || newValue == .help {
                    selectionBeforeSettings = oldValue
                }
                // Don't persist settings/help as saved selection
                if newValue != .settings && newValue != .help {
                    newValue?.save()
                }
                syncSelectedUsageProvider()
            }
            .onKeyPress(.escape) {
                if selection == .settings || selection == .help {
                    selection = selectionBeforeSettings
                    return .handled
                }
                return .ignored
            }
            .onAppear {
                // Intercept Cmd+W at the app level to close tabs instead of the window
                guard !keyMonitorInstalled else { return }
                keyMonitorInstalled = true
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if let notification = commandKeyNotification(event: event) {
                        NotificationCenter.default.post(name: notification, object: nil)
                        return nil // swallow the event
                    }
                    return event
                }
            }
    }

    private var navigationViewBase: some View {
        navigationViewProjectEvents
    }

    private var navigationViewEnvironment: some View {
        navigationSplitView
            .environmentObject(surfaceCache)
            .environmentObject(appEnvironment)
            .environmentObject(activityTracker)
            .environmentObject(agentStateStore)
            .environmentObject(claudeUsageStore)
            .environmentObject(codexUsageStore)
    }

    private var navigationViewLifecycle: some View {
        navigationViewEnvironment
            .onAppear {
                syncColumnVisibilityWithSidebarMode()
                appEnvironment.refresh()
                appEnvironment.refreshAllRepoInfo(projects: projects)
                appEnvironment.refreshPathValidity(projects: projects)
                appEnvironment.fetchOrigin(projects: projects)
                syncSelectedUsageProvider()
                codexUsageStore.refresh()
                headWatcher.sync(paths: currentWorktreePaths())
                // Apply saved appearance
                switch UserDefaults.standard.string(forKey: "dockyard.appearance") ?? "system" {
                case "light": NSApp.appearance = NSAppearance(named: .aqua)
                case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                default: NSApp.appearance = nil
                }
            }
            .onChange(of: sidebarModeRaw) { _, _ in
                syncColumnVisibilityWithSidebarMode()
            }
            .onChange(of: codingCLIRaw) { _, _ in
                syncSelectedUsageProvider()
            }
            .onChange(of: columnVisibility) { _, visibility in
                syncSidebarModeWithColumnVisibility(visibility)
            }
    }

    private var navigationViewShortcutEvents: some View {
        navigationViewLifecycle
            .onReceive(NotificationCenter.default.publisher(for: .switchToProject)) { _ in
                // Go back to project view from any workstream
                if let wsID = selection?.workstreamID,
                   let project = projects.first(where: { $0.workstreams.contains(where: { $0.id == wsID }) })
                {
                    selection = .project(project.id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextWorkstream)) { _ in
                cycleWorkstream(direction: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .prevWorkstream)) { _ in
                cycleWorkstream(direction: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextGlobalWorkstream)) { _ in
                cycleGlobalWorkstream(direction: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .prevGlobalWorkstream)) { _ in
                cycleGlobalWorkstream(direction: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextProject)) { _ in
                cycleProject(direction: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .prevProject)) { _ in
                cycleProject(direction: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .archiveWorkstream)) { _ in
                if let wsID = selection?.workstreamID {
                    workstreamToRemove = wsID
                }
            }
    }

    private var navigationViewProjectEvents: some View {
        navigationViewShortcutEvents
            .onReceive(NotificationCenter.default.publisher(for: .workstreamCreated)) { notification in
                guard let info = notification.userInfo,
                      let projectID = info["projectID"] as? UUID,
                      let workstream = info["workstream"] as? Workstream,
                      let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
                projects[index].workstreams.insert(workstream, at: 0)
                selection = .workstream(workstream.id)
                ProjectStore.save(projects)
                logger.warning("[Dockyard] workstreamCreated notification handled: \(workstream.name, privacy: .public)")
            }
            .onReceive(NotificationCenter.default.publisher(for: .workstreamWorktreeReady)) { notification in
                guard let info = notification.userInfo,
                      let workstreamID = info["workstreamID"] as? UUID,
                      let worktreePath = info["worktreePath"] as? String else { return }
                for pi in projects.indices {
                    if let wi = projects[pi].workstreams.firstIndex(where: { $0.id == workstreamID }) {
                        projects[pi].workstreams[wi].worktreePath = worktreePath
                        ProjectStore.save(projects)
                        appEnvironment.refreshPathValidity(projects: projects)
                        headWatcher.sync(paths: currentWorktreePaths())
                        logger.warning("[Dockyard] workstreamWorktreeReady: updated \(workstreamID, privacy: .public) with path \(worktreePath, privacy: .public)")
                        Telemetry.shared.track("workstream_created", url: "/workstream/create", title: "Workstream Created")
                        return
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workstreamCreationFailed)) { notification in
                guard let info = notification.userInfo,
                      let projectID = info["projectID"] as? UUID,
                      let workstreamID = info["workstreamID"] as? UUID,
                      let pi = projects.firstIndex(where: { $0.id == projectID }) else { return }
                projects[pi].workstreams.removeAll { $0.id == workstreamID }
                if case let .workstream(selectedID) = selection, selectedID == workstreamID {
                    selection = .project(projectID)
                }
                ProjectStore.save(projects)
                logger.warning("[Dockyard] workstreamCreationFailed: removed \(workstreamID, privacy: .public)")
            }
            .onReceive(NotificationCenter.default.publisher(for: .projectCreated)) { notification in
                guard let project = notification.userInfo?["project"] as? Project else { return }
                projects.insert(project, at: 0)
                selection = .project(project.id)
                ProjectStore.save(projects)
                appEnvironment.refreshPathValidity(projects: projects)
                appEnvironment.refreshAllRepoInfo(projects: projects)
                logger.warning("[Dockyard] projectCreated notification handled: \(project.name, privacy: .public)")
            }
            .onReceive(NotificationCenter.default.publisher(for: .worktreeHeadChanged)) { notification in
                guard let path = notification.object as? String else { return }
                Task { @MainActor in
                    await appEnvironment.refreshBranchAndDescription(for: path)
                    syncWorkstreamNamesFromBranches()
                }
            }
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                appEnvironment.refreshAllRepoInfo(projects: projects)
                appEnvironment.refreshPathValidity(projects: projects)
                appEnvironment.refreshAllBranchPRs(projects: projects)
                appEnvironment.fetchOrigin(projects: projects)
                syncWorkstreamNamesFromBranches()
                headWatcher.sync(paths: currentWorktreePaths())
                claudeUsageStore.refresh()
                if appEnvironment.toolStatus.codex.isInstalled || codexUsageStore.hasAnyData {
                    codexUsageStore.refresh()
                }
                syncSelectedUsageProvider()
            }
            .onReceive(NotificationCenter.default.publisher(for: .purgeWorkstream)) { notification in
                guard let wsID = notification.object as? UUID else { return }
                confirmPurge(wsID)
            }
    }

    private var navigationSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailView
        }
    }

    private var sidebarColumn: some View {
        ProjectSidebar(
            projects: $projectList.items,
            selection: $selection,
            onProjectsChanged: { ProjectStore.save(projects) },
            selectedUsageProvider: selectedUsageProvider,
            availableUsageProviders: availableUsageProviders,
            onPreviousUsageProvider: { cycleUsageProvider(direction: -1) },
            onNextUsageProvider: { cycleUsageProvider(direction: 1) }
        )
        .navigationSplitViewColumnWidth(
            min: sidebarColumnMinimumWidth,
            ideal: sidebarColumnIdealWidth,
            max: sidebarColumnMaximumWidth
        )
    }

    private var sidebarColumnMinimumWidth: CGFloat {
        sidebarMode == .collapsed ? 60 : 160
    }

    private var sidebarColumnIdealWidth: CGFloat {
        sidebarMode == .collapsed ? 60 : 200
    }

    private var sidebarColumnMaximumWidth: CGFloat {
        sidebarMode == .collapsed ? 60 : 350
    }

    /// All worktree paths currently known across projects, for the HEAD watcher.
    private func currentWorktreePaths() -> Set<String> {
        var paths: Set<String> = []
        for project in projects {
            for ws in project.workstreams {
                if let path = ws.worktreePath { paths.insert(path) }
            }
        }
        return paths
    }

    private func workstreamSubtitle(project: Project, workstream: Workstream) -> String {
        let branch = appEnvironment.branchName(for: workstream.worktreePath)
        if let branch {
            return "\(project.name) · \(branch)"
        }
        return project.name
    }

    private func openExternalTerminal() {
        let dir: String?
        if let ws = activeWorkstream, let project = activeProject {
            dir = ws.workingDirectory(projectDirectory: project.directory)
        } else if let project = activeProject {
            dir = project.directory
        } else {
            dir = nil
        }
        guard let dir else { return }
        let terminalBundleID = UserDefaults.standard.string(forKey: "dockyard.defaultTerminal") ?? ""
        if !terminalBundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleID)
        {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: dir)], withApplicationAt: appURL, configuration: config)
        } else if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: dir)], withApplicationAt: terminalURL, configuration: config)
        }
    }

    private func setSidebarMode(_ mode: SidebarMode) {
        if mode.isVisible {
            lastVisibleSidebarModeRaw = mode.rawValue
            columnVisibility = .all
        } else {
            columnVisibility = .detailOnly
        }
        sidebarModeRaw = mode.rawValue
    }

    private func toggleSidebarVisibility() {
        if sidebarMode == .hidden {
            setSidebarMode(lastVisibleSidebarMode)
        } else {
            lastVisibleSidebarModeRaw = sidebarMode.rawValue
            setSidebarMode(.hidden)
        }
    }

    private func toggleSidebarWidth() {
        let currentVisibleMode = sidebarMode == .hidden ? lastVisibleSidebarMode : sidebarMode
        let nextMode: SidebarMode = currentVisibleMode == .collapsed ? .expanded : .collapsed
        if sidebarMode == .hidden {
            lastVisibleSidebarModeRaw = nextMode.rawValue
        } else {
            setSidebarMode(nextMode)
        }
    }

    private func syncColumnVisibilityWithSidebarMode() {
        columnVisibility = sidebarMode == .hidden ? .detailOnly : .all
        if sidebarMode.isVisible {
            lastVisibleSidebarModeRaw = sidebarMode.rawValue
        }
    }

    private func syncSidebarModeWithColumnVisibility(_ visibility: NavigationSplitViewVisibility) {
        if visibility == .detailOnly {
            if sidebarMode.isVisible {
                lastVisibleSidebarModeRaw = sidebarMode.rawValue
                sidebarModeRaw = SidebarMode.hidden.rawValue
            }
        } else if sidebarMode == .hidden {
            sidebarModeRaw = lastVisibleSidebarMode.rawValue
        }
    }

    /// Update workstream names to match their branch name (without prefix).
    /// Called periodically so that when the agent renames a branch, the sidebar reflects it.
    private func syncWorkstreamNamesFromBranches() {
        var changed = false
        for pi in projects.indices {
            for wi in projects[pi].workstreams.indices {
                let ws = projects[pi].workstreams[wi]
                guard let branch = appEnvironment.branchName(for: ws.worktreePath) else { continue }
                // Strip the prefix (everything up to and including the last "/")
                let shortName = branch.contains("/") ? String(branch.split(separator: "/").last ?? Substring(branch)) : branch
                if shortName != ws.name {
                    projects[pi].workstreams[wi].name = shortName
                    changed = true
                }
            }
        }
        if changed {
            ProjectStore.save(projects)
        }
    }

    /// Cycle through workstreams within the active project.
    /// Only acts when a project or workstream is selected (not settings/help).
    private func cycleWorkstream(direction: Int) {
        guard let project = activeProject else { return }

        if selection?.workstreamID != nil || selection?.projectID != nil {
            guard let id = cycledWorkstreamID(in: project, selectedWorkstreamID: selection?.workstreamID, direction: direction) else { return }
            deferSelection(.workstream(id))
        }
    }

    /// Cycle through all workstreams globally across all projects.
    private func cycleGlobalWorkstream(direction: Int) {
        guard let id = cycledGlobalWorkstreamID(
            in: projects,
            selectedWorkstreamID: selection?.workstreamID,
            direction: direction
        ) else { return }
        deferSelection(.workstream(id))
    }

    private func deferSelection(_ target: SidebarSelection) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            guard selection != target else { return }
            selection = target
        }
    }

    /// Cycle through projects in sidebar display order.
    private func cycleProject(direction: Int) {
        guard let id = cycledProjectID(in: projects, selectedProjectID: activeProject?.id, direction: direction) else { return }
        selection = .project(id)
    }

    private func syncSelectedUsageProvider() {
        let preferred = preferredUsageProvider
        selectedUsageProvider = resolvedUsageMeterProvider(
            current: selectedUsageProvider,
            preferred: preferred,
            previousPreferred: previousPreferredUsageProvider,
            available: availableUsageProviders
        )
        previousPreferredUsageProvider = preferred
    }

    private func cycleUsageProvider(direction: Int) {
        selectedUsageProvider = cycledUsageMeterProvider(
            current: selectedUsageProvider,
            available: availableUsageProviders,
            direction: direction
        )
        previousPreferredUsageProvider = preferredUsageProvider
    }

    private func confirmPurge(_ wsID: UUID) {
        let ws = projects.flatMap(\.workstreams).first(where: { $0.id == wsID })
        purgeWarningMessage = ws.flatMap { WorkstreamArchiver.purgeWarning(for: $0) }
        workstreamToPurge = wsID
    }

    private func performRemove() {
        guard let wsID = workstreamToRemove,
              let projectIndex = projects.firstIndex(where: { $0.workstreams.contains(where: { $0.id == wsID }) }) else { return }
        WorkstreamArchiver.remove(wsID, in: &projects[projectIndex], surfaceCache: surfaceCache, tmuxPath: appEnvironment.toolStatus.tmux.path)
        ProjectStore.save(projects)
        workstreamToRemove = nil
    }

    private func performPurge() {
        guard let wsID = workstreamToPurge,
              let projectIndex = projects.firstIndex(where: { $0.workstreams.contains(where: { $0.id == wsID }) }) else { return }
        WorkstreamArchiver.purge(wsID, in: &projects[projectIndex], surfaceCache: surfaceCache, tmuxPath: appEnvironment.toolStatus.tmux.path)
        ProjectStore.save(projects)
        workstreamToPurge = nil
    }
}

enum ProjectStore {
    private static let userDefaultsKey = "dockyard.projects"

    static func load(defaults: UserDefaults = .standard) -> [Project] {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let projects = try? JSONDecoder().decode([Project].self, from: data)
        else { return [] }
        return projects
    }

    static func save(_ projects: [Project], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: userDefaultsKey)
    }
}
