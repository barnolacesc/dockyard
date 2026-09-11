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
    @StateObject private var appUpdater = AppUpdater()
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
    @StateObject private var agentActivityStore = AgentActivityStore.shared
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
    @State private var whatsNewReleases: [WhatsNewRelease] = []
    @State private var showWhatsNew = false
    @State private var projectTerminalProjectID: UUID?
    @AppStorage("dockyard.codingCLI") private var codingCLIRaw: String = ""
    @AppStorage(SidebarMode.storageKey) private var sidebarModeRaw = SidebarMode.expanded.rawValue
    @AppStorage(SidebarMode.lastVisibleStorageKey) private var lastVisibleSidebarModeRaw = SidebarMode.expanded.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        case .attention, .settings, .help:
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
        if selection == .attention {
            AttentionView(
                projects: projects,
                onSelectWorkstream: { selection = .workstream($0) }
            )
            .navigationTitle("Attention")
            .navigationSubtitle(AppConstants.appName)
        } else if selection == .settings {
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
            Group {
                if projectTerminalProjectID == project.id {
                    ProjectRootTerminalView(project: project) {
                        projectTerminalProjectID = nil
                    }
                } else {
                    ProjectOverviewView(
                        project: $projectList.items[projectIndex],
                        onSelectWorkstream: { wsID in selection = .workstream(wsID) },
                        onRemoveWorkstream: { wsID in workstreamToRemove = wsID },
                        onPurgeWorkstream: { wsID in confirmPurge(wsID) },
                        onProjectChanged: { ProjectStore.save(projects) }
                    )
                }
            }
            .navigationTitle(project.name)
            .navigationSubtitle(AppConstants.appName)
        } else {
            OnboardingView(toolStatus: appEnvironment.toolStatus, isDetecting: appEnvironment.isDetecting)
                .navigationTitle(AppConstants.appName)
        }
    }

    var body: some View {
        navigationView
            .overlay(alignment: .bottomTrailing) {
                if appUpdater.shouldPromptUpdate {
                    UpdateAvailableNotice(
                        commitsAhead: appUpdater.commitsAhead,
                        onUpdate: {
                            appUpdater.shouldPromptUpdate = false
                            appUpdater.applyUpdate()
                        },
                        onDismiss: { appUpdater.shouldPromptUpdate = false }
                    )
                    .padding(16)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : DesignMotion.interaction, value: appUpdater.shouldPromptUpdate)
            .shortcutHintOverlay()
            .tourOverlay()
            .sheet(isPresented: $showWhatsNew) {
                WhatsNewView(
                    releases: whatsNewReleases,
                    onShowTour: { flowID in
                        showWhatsNew = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            guard let flow = TourFlowCatalog.make(flowID: flowID) else { return }
                            TourController.shared.start(flow)
                        }
                    },
                    onClose: { showWhatsNew = false }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .openWhatsNew)) { _ in
                whatsNewReleases = WhatsNewCatalog.releases
                showWhatsNew = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .startTour)) { _ in
                TourController.shared.start(GettingStartedFlow.make())
            }
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
            .environmentObject(agentActivityStore)
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
                checkWhatsNewGate()
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
            .onReceive(NotificationCenter.default.publisher(for: .openAgentAttention)) { notification in
                guard let payload = notification.object as? AgentAttentionPayload else { return }
                guard projects.contains(where: {
                    $0.workstreams.contains(where: { $0.id == payload.workstreamID })
                }) else {
                    selection = .attention
                    return
                }
                selection = .workstream(payload.workstreamID)
                agentActivityStore.markRead(payload.eventID)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .focusAgent, object: nil)
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
            appUpdater: appUpdater,
            onOpenProjectTerminal: { projectID in
                projectTerminalProjectID = projectID
                selection = .project(projectID)
            },
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

    /// Once-per-version What's New: fresh installs just stamp the version.
    private func checkWhatsNewGate() {
        let current = AppConstants.version
        let lastSeen = UserDefaults.standard.string(forKey: WhatsNewGate.lastSeenKey)
        let releases = WhatsNewGate.releasesToPresent(
            current: current, lastSeen: lastSeen, catalog: WhatsNewCatalog.releases
        )
        UserDefaults.standard.set(current, forKey: WhatsNewGate.lastSeenKey)
        guard !releases.isEmpty else { return }
        whatsNewReleases = releases
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showWhatsNew = true
        }
    }
}

private struct UpdateAvailableNotice: View {
    let commitsAhead: Int
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("Update Available")
                    .font(.system(size: 13, weight: .semibold))

                Text("A new version of Dockyard is ready. It will rebuild and relaunch automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Update & Relaunch", action: onUpdate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Later")
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityValue(String(format: NSLocalizedString("%d updates available", comment: "Available source updates"), commitsAhead))
    }
}

enum ProjectStore {
    static let maximumSnapshotBytes = 1_048_576
    private static let userDefaultsKey = "dockyard.projects"

    private struct PersistedProject: Decodable {
        let value: Project?

        init(from decoder: Decoder) throws {
            value = try? Project(from: decoder)
        }
    }

    static func load(defaults: UserDefaults = .standard) -> [Project] {
        guard let data = defaults.data(forKey: userDefaultsKey),
              data.count <= maximumSnapshotBytes,
              let persistedProjects = try? JSONDecoder().decode([PersistedProject].self, from: data)
        else { return [] }
        return persistedProjects.compactMap(\.value)
    }

    static func save(_ projects: [Project], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: userDefaultsKey)
    }
}
