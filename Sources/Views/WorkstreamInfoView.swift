// ABOUTME: Info panel for a workstream showing metadata, environment, and docs.
// ABOUTME: First tab in the workspace, combining project info with run script controls.

import Darwin
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
    @State private var showUncommittedPopover = false
    @State private var isRunExpanded = false

    private enum PendingSetupAction { case inline, terminal }

    var body: some View {
        GeometryReader { geometry in
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

                if selectedDoc == nil {
                    ScrollView {
                        VStack(spacing: 14) {
                            heroHeader

                            gitWorktreeCard

                            pullRequestCard

                            codingAgentCard

                            scriptsCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .frame(maxWidth: 600)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Markdown content fills remaining space when a doc is selected
                    if let selected = selectedDoc,
                       let doc = docFiles.first(where: { $0.name == selected })
                    {
                        MarkdownContentView(markdown: doc.content)
                            .id(selected)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                // Doc tabs pinned above the run script bar
                if !docFiles.isEmpty {
                    Divider()
                    HStack(spacing: 4) {
                        ForEach(docFiles) { doc in
                            DocTabButton(
                                name: doc.name,
                                isActive: selectedDoc == doc.name,
                                action: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedDoc = selectedDoc == doc.name ? nil : doc.name
                                    }
                                }
                            )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(.bar)
                }

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
                        .frame(maxWidth: .infinity)
                        .frame(height: isRunExpanded ? max(220, geometry.size.height * 0.45) : nil)
                        .frame(minHeight: 32)
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
                            runStarted: $runStarted,
                            isExpanded: $isRunExpanded
                        )
                        .frame(height: isRunExpanded ? max(220, geometry.size.height * 0.45) : nil)
                        .frame(minHeight: 32)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var heroHeader: some View {
        VStack(spacing: 4) {
            if let icon = projectIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.sm, style: .continuous))
                    .imageOutline(radius: DesignRadius.sm)
            }
            Text(projectName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            if let desc = appEnv.taskDescription(for: workingDirectory), !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(workstreamName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(workstreamName)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var gitWorktreeCard: some View {
        if let branch = branchName {
            let state = appEnv.worktreeState(for: workingDirectory)

            InfoCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {
                        // Left column
                        VStack(alignment: .leading, spacing: 8) {
                            infoField(label: "Branch") {
                                HStack(spacing: 4) {
                                    Text(branch)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.primary)
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
                            }

                            infoField(label: "Base") {
                                Text(formattedBaseString(baseBranch: state.baseBranch, createdDate: state.branchCreatedDate))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Right column
                        VStack(alignment: .leading, spacing: 8) {
                            infoField(label: "Status") {
                                if state.uncommittedCount > 0 {
                                    Button {
                                        showUncommittedPopover = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("\(state.uncommittedCount) files")
                                                .font(.system(size: 12, design: .monospaced))
                                                .tabularNumbers()
                                                .foregroundStyle(DesignColor.statusWarning)
                                            Image(systemName: "info.circle")
                                                .font(.system(size: 10))
                                                .foregroundStyle(DesignColor.statusWarning.opacity(0.8))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showUncommittedPopover) {
                                        UncommittedChangesPopover(
                                            path: workingDirectory,
                                            title: workstreamName,
                                            onDiscard: {
                                                appEnv.refreshWorktreeState(for: workingDirectory, projectDirectory: projectDirectory, force: true)
                                            },
                                            onCleanUntracked: {
                                                appEnv.refreshWorktreeState(for: workingDirectory, projectDirectory: projectDirectory, force: true)
                                            }
                                        )
                                    }
                                } else {
                                    Text("Clean")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(DesignColor.statusSuccess)
                                }
                            }

                            if workingDirectory != projectDirectory, let worktreeCreated = state.worktreeCreatedDate {
                                infoField(label: "Age") {
                                    HStack(spacing: 6) {
                                        Text(formatWorktreeAge(worktreeCreated))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        if state.commitsAhead > 0 {
                                            Text("·")
                                                .foregroundStyle(.tertiary)
                                            Text("↑ \(state.commitsAhead)")
                                                .font(.system(size: 12, design: .monospaced))
                                                .tabularNumbers()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } else if state.commitsAhead > 0 {
                                infoField(label: "Ahead") {
                                    Text("↑ \(state.commitsAhead) commits")
                                        .font(.system(size: 12, design: .monospaced))
                                        .tabularNumbers()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider().padding(.vertical, 1)

                    // Directory row
                    HStack(alignment: .center, spacing: 8) {
                        Text("Directory")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)

                        Text(workingDirectory.abbreviatedPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 4)

                        HStack(spacing: 2) {
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
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pullRequestCard: some View {
        if appEnv.ghAvailable, let branch = branchName,
           let pr = appEnv.githubPR(for: projectDirectory, branch: branch)
        {
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "Pull Request")

                InfoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        let prColor: Color = pr.state == "MERGED" ? DesignColor.statusMerged : pr.state == "OPEN" ? DesignColor.statusSuccess : .secondary
                        if let url = URL(string: pr.url) {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: pr.state == "MERGED" ? "arrow.triangle.merge" : "arrow.triangle.pull")
                                        .foregroundStyle(prColor)
                                    Text(verbatim: "#\(pr.number)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .tabularNumbers()
                                    Text(pr.title)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(LocalizedStringKey(pr.state == "MERGED" ? "Merged" : pr.state == "CLOSED" ? "Closed" : "Open"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(prColor)
                                }
                                .frame(minHeight: 24)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open on GitHub")
                        }
                        PRChecksBadge(pr: pr, directory: projectDirectory)

                        if pr.state == "MERGED" {
                            Divider()
                            HStack {
                                Text("This branch has been merged.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Purge") {
                                    NotificationCenter.default.post(name: .purgeWorkstream, object: workstreamID)
                                }
                                .controlSize(.small)
                                .foregroundStyle(DesignColor.statusMerged)
                            }
                        }
                    }
                }
            }
        }
    }

    private var codingAgentCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionHeader(title: "Coding Agent")

            InfoCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Agent")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)

                        Picker("", selection: $workstreamCodingCLI) {
                            Text(defaultCodingAgentLabel).tag(String?.none)
                            ForEach(CodingCLI.allCases) { cli in
                                Text(cli.displayName).tag(String?.some(cli.rawValue))
                            }
                        }
                        .labelsHidden()
                        .tourAnchor(.agentPicker)

                        Spacer()
                    }

                    if !appEnv.toolStatus.status(for: selectedCodingCLI).isInstalled {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignColor.statusWarning)
                            Text(selectedCodingCLI.missingTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link(selectedCodingCLI.installLabel, destination: selectedCodingCLI.installURL)
                                .font(.caption)
                        }
                        .padding(.leading, 58)
                    }

                    Divider().padding(.vertical, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $bypassPermissions) {
                            Text("Dangerously skip permissions")
                                .font(.system(size: 12))
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!selectedCodingCLI.capabilities.supportsDangerousPermissionBypass)

                        HStack(spacing: 6) {
                            Text("Saved for the next Coding Agent start.")
                                .font(.caption2)
                                .foregroundStyle(bypassPermissions ? DesignColor.statusWarning : .secondary)

                            if livePermissionControlAvailable {
                                Button("Change live permissions…", action: onChangeLivePermissions)
                                    .font(.caption2)
                                    .buttonStyle(.borderless)
                            }
                        }
                        .padding(.leading, 20)

                        if let livePermissionHint {
                            Text(livePermissionHint)
                                .font(.caption2)
                                .foregroundStyle(DesignColor.statusWarning)
                                .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    private var scriptsCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionHeader(title: "Scripts")
                Spacer()
                if isEditingConfig {
                    Button("Cancel", action: cancelConfigEditing)
                        .font(.caption)
                        .buttonStyle(.borderless)
                    Button("Save", action: saveEditedConfig)
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canSaveEditedConfig)
                } else if hasEditableScriptConfig {
                    if let source = scriptConfig.source {
                        Text(source)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Button("Regenerate…", action: generateConfig)
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .disabled(isDetectingStack)
                    Button("Edit", action: beginConfigEditing)
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }

            InfoCard {
                scriptsSectionContent
            }
        }
    }

    private func infoField<Content: View>(label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            content()
        }
    }

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
        VStack(alignment: .leading, spacing: 8) {
            if let setup = scriptConfig.setup {
                alignedScriptRow(label: "Setup", value: setup)
            }
            if let run = scriptConfig.run {
                alignedScriptRow(label: "Run", value: run)
            }
            if let teardown = scriptConfig.teardown {
                alignedScriptRow(label: "Teardown", value: teardown)
            }
            if let expectedPort = scriptConfig.expectedPort {
                alignedScriptRow(label: "Expected Port", value: "\(expectedPort)")
            }
        }
        .padding(.vertical, 2)
    }

    private func alignedScriptRow(label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var configEditorRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            alignedEditorRow(label: "Setup", text: $editSetup)
            alignedEditorRow(label: "Run", text: $editRun)
            alignedEditorRow(label: "Teardown", text: $editTeardown)
            alignedEditorRow(label: "Expected Port", text: $editPortText)

            if editParseResult.validationError == .invalidPort {
                Label("Port must be between 1 and 65535", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 88)
            }
            if let editWriteError {
                Label(editWriteError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 88)
            }
        }
        .padding(.vertical, 2)
    }

    private func alignedEditorRow(label: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            TextField("", text: text)
                .font(.system(size: 12, design: .monospaced))
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

private struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }
}

private struct InfoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
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
                .font(.system(size: 11))
                .foregroundStyle(color ?? (isHovering ? Color.primary : Color.secondary))
                .frame(width: 20, height: 20)
                .background(isHovering ? Color.primary.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
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
    static let maximumPreviewBytes = 1_048_576

    static func loadFrom(directory: String) -> [DocFile] {
        let projectRoot = URL(fileURLWithPath: directory, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var found: [DocFile] = []
        for name in standardNames {
            let documentURL = projectRoot
                .appendingPathComponent(name, isDirectory: false)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard isContained(documentURL, by: projectRoot),
                  let data = readBoundedRegularFile(at: documentURL),
                  data.count >= 20,
                  let content = String(data: data, encoding: .utf8)
            else { continue }
            found.append(DocFile(name: name, content: content))
        }
        return found
    }

    private static func readBoundedRegularFile(at url: URL) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size >= 0,
              metadata.st_size <= off_t(maximumPreviewBytes)
        else {
            return nil
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))

        do {
            while data.count <= maximumPreviewBytes {
                let remaining = maximumPreviewBytes + 1 - data.count
                let chunkSize = min(64 * 1024, remaining)
                guard chunkSize > 0 else { break }
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch {
            return nil
        }

        guard data.count <= maximumPreviewBytes else { return nil }
        return data
    }

    private static func isContained(_ item: URL, by directory: URL) -> Bool {
        let directoryComponents = directory.pathComponents
        let itemComponents = item.pathComponents
        return itemComponents.count > directoryComponents.count
            && itemComponents.starts(with: directoryComponents)
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
                .font(.system(size: 11, weight: isActive ? .medium : .regular, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.primary.opacity(0.1) : (isHovering ? Color.primary.opacity(0.05) : .clear))
                .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
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

struct GenerateConfigSheet: View {
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
