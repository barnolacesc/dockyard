// ABOUTME: Info panel for a workstream showing metadata, environment, and docs.
// ABOUTME: First tab in the workspace, combining project info with run script controls.

import SwiftUI

struct WorkstreamInfoView: View {
    let workstreamID: UUID
    let workstreamName: String
    let workingDirectory: String
    let projectName: String
    let projectDirectory: String
    var scriptConfig: ScriptConfig = .empty
    var useTmux: Bool = false
    var environmentVars: [String: String] = [:]
    @Binding var workstreamCodingCLI: String?
    @Binding var bypassPermissions: Bool
    @Binding var runStoppedManually: Bool
    @Binding var runStarted: Bool
    var sessionMode: TerminalSessionMode = .standard
    @ObservedObject var setupRunner: SetupRunner
    var livePermissionControlAvailable: Bool = false
    var livePermissionHint: String?
    var onRunSetupInTerminal: () -> Void = {}
    var onConfigGenerated: () -> Void = {}
    var onChangeLivePermissions: () -> Void = {}

    @EnvironmentObject var appEnv: AppEnvironment
    @AppStorage("dockyard.defaultTerminal") private var defaultTerminal: String = ""
    @AppStorage("dockyard.codingCLI") private var globalCodingCLIRaw: String = ""
    @State private var branchName: String?
    @State private var copiedBranch = false
    @State private var copiedPath = false
    @State private var docFiles: [DocFile] = []
    @State private var selectedDoc: String?
    @State private var projectIcon: NSImage?
    @State private var showGenerateSheet = false
    @State private var isDetectingStack = false
    @State private var configDraft: DockyardConfigDraft?
    @State private var existingConfigText: String?
    @State private var writeError: String?
    @State private var isEditingConfig = false
    @State private var editSetup = ""
    @State private var editRun = ""
    @State private var editTeardown = ""
    @State private var editPortText = ""
    @State private var editWriteError: String?
    @State private var showScriptApproval = false
    @State private var pendingSetupAction: PendingSetupAction?

    private enum PendingSetupAction { case inline, terminal }

    var body: some View {
        VStack(spacing: 0) {
            if scriptConfig.setup != nil, setupRunner.state != .succeeded {
                SetupStatusBanner(
                    script: scriptConfig.setup!,
                    state: setupRunner.state,
                    logTail: setupRunner.logTail,
                    onStart: { requestSetupStart(.inline) },
                    onCancel: { setupRunner.cancel() },
                    onRunInTerminal: { requestSetupStart(.terminal) }
                )
            }
            Form {
                // Hero header
                Section {
                    VStack(spacing: 4) {
                        if let icon = projectIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous))
                                .imageOutline(radius: DesignRadius.lg)
                        }
                        Text(projectName)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        if let desc = appEnv.taskDescription(for: workingDirectory), !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 22, weight: .bold))
                                .multilineTextAlignment(.center)
                            Text(workstreamName)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(workstreamName)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    if let branch = branchName {
                        LabeledContent {
                            HStack(spacing: 4) {
                                Text(branch)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                DirectoryActionButton(
                                    icon: copiedBranch ? "checkmark" : "doc.on.doc",
                                    color: copiedBranch ? DesignColor.statusSuccess : nil,
                                    tooltip: "Copy branch name"
                                ) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(branch, forType: .string)
                                    copiedBranch = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedBranch = false }
                                }
                            }
                        } label: {
                            Text("Branch")
                        }
                        
                        let state = appEnv.worktreeState(for: workingDirectory)
                        
                        if state.commitsAhead > 0 {
                            LabeledContent {
                                Text("↑ \(state.commitsAhead) commits")
                                    .font(.system(.body, design: .monospaced))
                                    .tabularNumbers()
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text("Ahead")
                            }
                        }
                        
                        LabeledContent {
                            if state.uncommittedCount > 0 {
                                Text("\(state.uncommittedCount) files")
                                    .font(.system(.body, design: .monospaced))
                                    .tabularNumbers()
                                    .foregroundStyle(DesignColor.statusWarning)
                            } else {
                                Text("Clean")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Text("Uncommitted")
                        }
                        
                        LabeledContent {
                            Text(formattedBaseString(baseBranch: state.baseBranch, createdDate: state.branchCreatedDate))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } label: {
                            Text("Base")
                        }
                        
                        if workingDirectory != projectDirectory, let worktreeCreated = state.worktreeCreatedDate {
                            LabeledContent {
                                Text(formatWorktreeAge(worktreeCreated))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text("Worktree Age")
                            }
                        }
                    }

                    LabeledContent {
                        HStack(spacing: 4) {
                            Text(workingDirectory.abbreviatedPath)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            DirectoryActionButton(
                                icon: copiedPath ? "checkmark" : "doc.on.doc",
                                color: copiedPath ? DesignColor.statusSuccess : nil,
                                tooltip: "Copy path"
                            ) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(workingDirectory, forType: .string)
                                copiedPath = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedPath = false }
                            }
                            DirectoryActionButton(
                                icon: "terminal",
                                tooltip: "Open in external terminal"
                            ) {
                                openInTerminal(path: workingDirectory)
                            }
                            if let githubURL = appEnv.githubURL(for: projectDirectory, branch: appEnv.branchName(for: workingDirectory)) {
                                DirectoryActionButton(
                                    assetIcon: "github",
                                    tooltip: "Open on GitHub"
                                ) {
                                    NSWorkspace.shared.open(githubURL)
                                }
                            }
                        }
                    } label: {
                        Text("Directory")
                    }
                }

                if appEnv.ghAvailable, let branch = branchName,
                   let pr = appEnv.githubPR(for: projectDirectory, branch: branch)
                {
                    Section("Pull Request") {
                        let prColor: Color = pr.state == "MERGED" ? DesignColor.statusMerged : pr.state == "OPEN" ? DesignColor.statusSuccess : .secondary
                        LabeledContent {
                            HStack(spacing: 6) {
                                Image(systemName: pr.state == "MERGED" ? "arrow.triangle.merge" : "arrow.triangle.pull")
                                    .foregroundStyle(prColor)
                                Text(verbatim: "#\(pr.number)")
                                    .font(.system(.body, design: .monospaced))
                                    .tabularNumbers()
                                Text(pr.title)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } label: {
                            Text(pr.state.capitalized)
                                .foregroundStyle(prColor)
                        }

                        if pr.state == "MERGED" {
                            HStack {
                                Text("This branch has been merged.")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Purge") {
                                    NotificationCenter.default.post(name: .purgeWorkstream, object: workstreamID)
                                }
                                .foregroundStyle(DesignColor.statusMerged)
                            }
                        }
                    }
                }

                Section("Coding Agent") {
                    Picker("Coding Agent", selection: $workstreamCodingCLI) {
                        Text(defaultCodingAgentLabel).tag(String?.none)
                        ForEach(CodingCLI.allCases) { cli in
                            Text(cli.displayName).tag(String?.some(cli.rawValue))
                        }
                    }
                    .tourAnchor(.agentPicker)

                    Text("Use Default follows the Coding Agent selected in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !appEnv.toolStatus.status(for: selectedCodingCLI).isInstalled {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(DesignColor.statusWarning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedCodingCLI.missingTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Link(selectedCodingCLI.installLabel, destination: selectedCodingCLI.installURL)
                                    .font(.caption)
                            }
                        }
                    }

                    Toggle("Dangerously skip permissions", isOn: $bypassPermissions)

                    Text("Saved for the next Coding Agent start.")
                        .font(.caption)
                        .foregroundStyle(bypassPermissions ? DesignColor.statusWarning : .secondary)

                    if livePermissionControlAvailable {
                        Button("Change live permissions...", action: onChangeLivePermissions)
                            .buttonStyle(.borderless)
                    }

                    if let livePermissionHint {
                        Text(livePermissionHint)
                            .font(.caption)
                            .foregroundStyle(DesignColor.statusWarning)
                    }
                }

                Section {
                    scriptsSectionContent
                } header: {
                    HStack {
                        Text("Scripts")
                        Spacer()
                        if isEditingConfig {
                            Button("Cancel", action: cancelConfigEditing)
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                .onHover { hovering in
                                    updatePointingHand(hovering, enabled: true)
                                }
                            Button("Save", action: saveEditedConfig)
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                .disabled(!canSaveEditedConfig)
                                .onHover { hovering in
                                    updatePointingHand(hovering, enabled: canSaveEditedConfig)
                                }
                        } else if hasEditableScriptConfig {
                            if let source = scriptConfig.source {
                                Text(source)
                                    .font(.caption2)
                                    .foregroundStyle(.quaternary)
                            }
                            Button("Regenerate…", action: generateConfig)
                                .font(.caption2)
                                .pressable()
                                .disabled(isDetectingStack)
                                .onHover { hovering in
                                    updatePointingHand(hovering, enabled: !isDetectingStack)
                                }
                            Button("Edit", action: beginConfigEditing)
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                .onHover { hovering in
                                    updatePointingHand(hovering, enabled: true)
                                }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            // Environment (run script) section
            if scriptConfig.run != nil || scriptConfig.loadError != nil {
                Divider()
                if sessionMode == .waitingForTools {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Checking terminal tools...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EnvironmentTabView(
                        workstreamID: workstreamID,
                        workingDirectory: workingDirectory,
                        projectDirectory: projectDirectory,
                        projectName: projectName,
                        workstreamName: workstreamName,
                        scriptConfig: scriptConfig,
                        useTmux: useTmux,
                        environmentVars: environmentVars,
                        runStoppedManually: $runStoppedManually,
                        runStarted: $runStarted
                    )
                }
            } else {
                // Markdown content fills remaining space when a doc is selected
                if let selected = selectedDoc,
                   let doc = docFiles.first(where: { $0.name == selected })
                {
                    Divider()
                    MarkdownContentView(markdown: doc.content)
                        .id(selected)
                }
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadInfo() }
        .sheet(isPresented: $showGenerateSheet) {
            GenerateConfigSheet(
                draft: configDraft ?? DockyardConfigDraft(),
                existingConfigText: existingConfigText,
                projectName: projectName,
                writeError: writeError,
                onConfirm: confirmWrite,
                onCancel: { showGenerateSheet = false }
            )
        }
        .sheet(isPresented: $showScriptApproval) {
            ScriptApprovalSheet(
                source: scriptConfig.source,
                setup: scriptConfig.setup,
                run: scriptConfig.run,
                teardown: scriptConfig.teardown,
                onApprove: {
                    ScriptTrustStore.trust(projectDirectory: projectDirectory, config: scriptConfig)
                    showScriptApproval = false
                    if let action = pendingSetupAction { performSetupAction(action) }
                    pendingSetupAction = nil
                },
                onDecline: {
                    showScriptApproval = false
                    pendingSetupAction = nil
                }
            )
        }
    } // body

    private func requestSetupStart(_ action: PendingSetupAction) {
        guard ScriptTrustStore.isTrusted(projectDirectory: projectDirectory, config: scriptConfig) else {
            pendingSetupAction = action
            showScriptApproval = true
            return
        }
        performSetupAction(action)
    }

    private func performSetupAction(_ action: PendingSetupAction) {
        switch action {
        case .inline:
            guard let setup = scriptConfig.setup else { return }
            setupRunner.start(script: setup, workingDirectory: workingDirectory, environmentVars: environmentVars)
        case .terminal:
            onRunSetupInTerminal()
        }
    }

    @ViewBuilder
    private var scriptsSectionContent: some View {
        if isEditingConfig {
            configEditorRows
        } else if hasEditableScriptConfig {
            configReadRows
        } else {
            configEmptyState
        }
    }

    @ViewBuilder
    private var configReadRows: some View {
        if let setup = scriptConfig.setup {
            LabeledContent("Setup") {
                Text(setup)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        if let run = scriptConfig.run {
            LabeledContent("Run") {
                Text(run)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        if let teardown = scriptConfig.teardown {
            LabeledContent("Teardown") {
                Text(teardown)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        if let expectedPort = scriptConfig.expectedPort {
            LabeledContent("Expected Port") {
                Text("\(expectedPort)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var configEditorRows: some View {
        LabeledContent("Setup") {
            TextField("", text: $editSetup)
                .font(.system(.body, design: .monospaced))
        }
        LabeledContent("Run") {
            TextField("", text: $editRun)
                .font(.system(.body, design: .monospaced))
        }
        LabeledContent("Teardown") {
            TextField("", text: $editTeardown)
                .font(.system(.body, design: .monospaced))
        }
        LabeledContent("Expected Port") {
            TextField("", text: $editPortText)
                .font(.system(.body, design: .monospaced))
        }
        if editParseResult.validationError == .invalidPort {
            Label("Port must be between 1 and 65535", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let editWriteError {
            Label(editWriteError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var configEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No setup or run scripts are configured for this project.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(action: generateConfig) {
                    HStack(spacing: 6) {
                        if isDetectingStack {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text("Generate .dockyard.json")
                    }
                }
                .disabled(isDetectingStack)
                .tourAnchor(.generateConfigButton)

                Button("Create manually", action: beginBlankConfigEditing)
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .disabled(isDetectingStack)
                    .onHover { hovering in
                        updatePointingHand(hovering, enabled: !isDetectingStack)
                    }
            }
            Text("Detect your stack automatically, or fill in the commands yourself.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var hasEditableScriptConfig: Bool {
        scriptConfig.hasAnyScript || scriptConfig.expectedPort != nil
    }

    private var editParseResult: DockyardConfigDraft.FieldParseResult {
        DockyardConfigDraft.parseFields(
            setup: editSetup,
            run: editRun,
            teardown: editTeardown,
            portText: editPortText
        )
    }

    private var canSaveEditedConfig: Bool {
        editParseResult.validationError == nil && !editParseResult.draft.isEmpty
    }

    private func generateConfig() {
        guard !isDetectingStack else { return }
        isDetectingStack = true
        writeError = nil
        let dir = projectDirectory
        Task.detached {
            let draft = StackDetector.detect(at: dir)
            let path = URL(fileURLWithPath: dir).appendingPathComponent(".dockyard.json").path
            let existing = try? String(contentsOfFile: path, encoding: .utf8)
            await MainActor.run {
                configDraft = draft
                existingConfigText = existing
                isDetectingStack = false
                showGenerateSheet = true
            }
        }
    }

    private func beginConfigEditing() {
        seedConfigEditingFieldsFromScriptConfig()
        editWriteError = nil
        isEditingConfig = true
    }

    private func beginBlankConfigEditing() {
        editSetup = ""
        editRun = ""
        editTeardown = ""
        editPortText = ""
        editWriteError = nil
        isEditingConfig = true
    }

    private func cancelConfigEditing() {
        seedConfigEditingFieldsFromScriptConfig()
        editWriteError = nil
        isEditingConfig = false
    }

    private func saveEditedConfig() {
        let result = editParseResult
        guard result.validationError == nil, !result.draft.isEmpty else { return }

        do {
            try DockyardConfigWriter.write(result.draft, to: projectDirectory)
            // The user typed these scripts themselves; no approval prompt needed.
            ScriptTrustStore.trust(projectDirectory: projectDirectory, setup: result.draft.setup, run: result.draft.run, teardown: result.draft.teardown)
            editWriteError = nil
            isEditingConfig = false
            onConfigGenerated()
        } catch {
            editWriteError = error.localizedDescription
        }
    }

    private func seedConfigEditingFieldsFromScriptConfig() {
        editSetup = scriptConfig.setup ?? ""
        editRun = scriptConfig.run ?? ""
        editTeardown = scriptConfig.teardown ?? ""
        editPortText = scriptConfig.expectedPort.map(String.init) ?? ""
    }

    private func updatePointingHand(_ hovering: Bool, enabled: Bool) {
        if hovering, enabled {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }

    private func confirmWrite() {
        guard let draft = configDraft, !draft.isEmpty else {
            showGenerateSheet = false
            return
        }
        do {
            try DockyardConfigWriter.write(draft, to: projectDirectory)
            // The user reviewed this draft in the generate sheet before confirming.
            ScriptTrustStore.trust(projectDirectory: projectDirectory, setup: draft.setup, run: draft.run, teardown: draft.teardown)
            writeError = nil
            showGenerateSheet = false
            onConfigGenerated()
        } catch {
            writeError = error.localizedDescription
        }
    }

    private var effectiveCodingCLIStoredValue: String {
        effectiveCodingCLIRaw(workstream: workstreamCodingCLI, global: globalCodingCLIRaw)
    }

    private var selectedCodingCLI: CodingCLI {
        appEnv.toolStatus.resolvedCodingCLI(storedValue: effectiveCodingCLIStoredValue)
    }

    private var defaultCodingAgentLabel: String {
        let defaultCLI = appEnv.toolStatus.resolvedCodingCLI(storedValue: globalCodingCLIRaw)
        return String(format: NSLocalizedString("Use Default (%@)", comment: ""), defaultCLI.displayName)
    }

    private func formattedBaseString(baseBranch: String, createdDate: Date?) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let dateStr = createdDate.map { dateFormatter.string(from: $0) } ?? ""
        return baseBranch + (dateStr.isEmpty ? "" : " · \(dateStr)")
    }

    private func formatWorktreeAge(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "Created today")
        }
        let components = calendar.dateComponents([.month, .weekOfYear, .day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date()))
        if let month = components.month, month > 0 {
            return "\(month) \(month == 1 ? "month" : "months")"
        } else if let week = components.weekOfYear, week > 0 {
            return "\(week) \(week == 1 ? "week" : "weeks")"
        } else if let day = components.day, day > 0 {
            return "\(day) \(day == 1 ? "day" : "days")"
        }
        return String(localized: "Created today")
    }

    private func openInTerminal(path: String) {
        if !defaultTerminal.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: defaultTerminal)
        {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: config)
        } else if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminalURL, configuration: config)
        }
    }

    private nonisolated static let iconPaths = [
        "icon.svg", "icon.png",
        ".github/icon.svg", ".github/icon.png",
        "logo.svg", "logo.png",
    ]

    private nonisolated static func findProjectIcon(in directory: String) -> NSImage? {
        let base = URL(fileURLWithPath: directory)
        for relative in iconPaths {
            let path = base.appendingPathComponent(relative).path
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }

    private nonisolated static func findProjectIconPath(in directory: String) -> String? {
        let base = URL(fileURLWithPath: directory)
        for relative in iconPaths {
            let path = base.appendingPathComponent(relative).path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func loadInfo() {
        let workingDir = workingDirectory
        let gitHubProjectDir = projectDirectory
        Task.detached {
            let branch = GitOperations.repoInfo(at: workingDir).branch
            await updateBranchInfo(branch, projectDirectory: gitHubProjectDir)
        }

        let projDir = projectDirectory
        Task.detached {
            let iconPath = Self.findProjectIconPath(in: projDir)
            await updateProjectIcon(iconPath: iconPath)
        }

        let dir = workingDirectory
        Task.detached {
            let found = DocFile.loadFrom(directory: dir)
            await updateDocFiles(found)
        }
    }

    @MainActor
    private func updateBranchInfo(_ branch: String?, projectDirectory: String) {
        branchName = branch
        appEnv.refreshGitHubInfo(for: projectDirectory, branch: branch)
    }

    @MainActor
    private func updateProjectIcon(iconPath: String?) {
        if let iconPath {
            projectIcon = NSImage(contentsOfFile: iconPath)
        } else {
            projectIcon = nil
        }
    }

    @MainActor
    private func updateDocFiles(_ docFiles: [DocFile]) {
        self.docFiles = docFiles
    }
}

// MARK: - Directory row with copy and open-in-terminal actions

struct DirectoryRow: View {
    let path: String
    var defaultTerminal: String = ""
    var githubURL: URL?

    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            Text(path.abbreviatedPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            DirectoryActionButton(
                icon: copied ? "checkmark" : "doc.on.doc",
                color: copied ? DesignColor.statusSuccess : nil,
                tooltip: "Copy path"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }

            DirectoryActionButton(
                icon: "terminal",
                tooltip: "Open in external terminal"
            ) {
                openInTerminal()
            }

            if let githubURL {
                DirectoryActionButton(
                    assetIcon: "github",
                    tooltip: "Open on GitHub"
                ) {
                    NSWorkspace.shared.open(githubURL)
                }
            }
        }
    }

    private func openInTerminal() {
        if !defaultTerminal.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: defaultTerminal)
        {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: config)
        } else if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminalURL, configuration: config)
        }
    }
}

private struct DirectoryActionButton: View {
    var icon: String = ""
    var assetIcon: String?
    var color: Color? = nil
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            (assetIcon.map { Image($0) } ?? Image(systemName: icon))
                .font(.system(size: 12))
                .foregroundStyle(color ?? (isHovering ? Color.primary : Color.secondary))
                .frame(width: 22, height: 22)
                .background(isHovering ? Color.primary.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                .frame(minWidth: 40, minHeight: 40)
        }
        .pressable()
        .onHover { isHovering = $0 }
        .help(tooltip)
        .accessibilityLabel(tooltip)
    }
}

struct DocFile: Identifiable {
    let name: String
    let content: String
    var id: String {
        name
    }

    static let standardNames = ["README.md", "CLAUDE.md", "AGENTS.md"]

    static func loadFrom(directory: String) -> [DocFile] {
        let fm = FileManager.default
        var found: [DocFile] = []
        for name in standardNames {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  attrs[.type] as? FileAttributeType == .typeRegular
            else { continue }
            if let data = fm.contents(atPath: path),
               data.count >= 20,
               let content = String(data: data, encoding: .utf8)
            {
                found.append(DocFile(name: name, content: content))
            }
        }
        return found
    }
}

struct DocTabButton: View {
    let name: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 10, weight: isActive ? .medium : .regular, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.primary.opacity(0.08) : (isHovering ? Color.primary.opacity(0.04) : .clear))
                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(minHeight: 40)
        }
        .pressable()
        .onHover { isHovering = $0 }
    }
}

private struct SetupStatusBanner: View {
    let script: String
    let state: SetupRunner.State
    let logTail: String
    let onStart: () -> Void
    let onCancel: () -> Void
    let onRunInTerminal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                switch state {
                case .idle:
                    Image(systemName: "info.circle.fill").foregroundStyle(DesignColor.statusInfo)
                    Text("Setup not run").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Run setup") { onStart() }
                        .controlSize(.small)
                case .running:
                    ProgressView().controlSize(.small)
                    Text("Setup running…").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(script).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: 150)
                    Spacer()
                    Button("Cancel") { onCancel() }
                        .controlSize(.small)
                case let .failed(code):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DesignColor.statusError)
                    Text("Setup failed (exit \(code))").font(.system(size: 11)).tabularNumbers().foregroundStyle(.secondary)
                    Spacer()
                    Button("Run in terminal") { onRunInTerminal() }
                        .controlSize(.small)
                    Button("Retry") { onStart() }
                        .controlSize(.small)
                case .succeeded:
                    EmptyView()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.15))
            
            if case .failed = state, !logTail.isEmpty {
                Divider()
                DisclosureGroup("View log") {
                    ScrollView {
                        Text(logTail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                    .padding(.top, 4)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(backgroundColor.opacity(0.1))
            }
            Divider()
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .idle: return .blue
        case .running: return .yellow
        case .failed: return .red
        case .succeeded: return .clear
        }
    }
}

// MARK: - Generate .dockyard.json confirmation sheet

private struct GenerateConfigSheet: View {
    let draft: DockyardConfigDraft
    let existingConfigText: String?
    let projectName: String
    let writeError: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Color.accentColor)
                Text("Generate .dockyard.json")
                    .font(.headline)
            }

            if draft.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn't detect a stack", systemImage: "questionmark.folder")
                        .font(.subheadline)
                    Text("Dockyard couldn't recognize a known stack in this project. Add setup and run commands manually to .dockyard.json.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if existingConfigText != nil {
                    Text("A .dockyard.json already exists. Review the proposed replacement before writing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(format: NSLocalizedString("Proposed .dockyard.json for %@:", comment: ""), projectName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let existing = existingConfigText {
                    HStack(alignment: .top, spacing: 10) {
                        jsonColumn(title: NSLocalizedString("Existing", comment: ""), content: existing)
                        jsonColumn(title: NSLocalizedString("Proposed", comment: ""), content: draft.jsonString())
                    }
                } else {
                    jsonBox(draft.jsonString())
                }
            }

            if let writeError {
                Label(writeError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DesignColor.statusError)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if draft.isEmpty {
                    Button("Close", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    if existingConfigText != nil {
                        Button("Overwrite", action: onConfirm)
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Write File", action: onConfirm)
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: existingConfigText != nil ? 620 : 440)
    }

    private func jsonColumn(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            jsonBox(content)
        }
    }

    private func jsonBox(_ content: String) -> some View {
        ScrollView {
            Text(content)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
        .padding(8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
    }
}
