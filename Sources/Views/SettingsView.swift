// ABOUTME: Application settings pane displayed in the detail area.
// ABOUTME: Environment, general, coding agent, and advanced settings.

import SwiftUI

struct SettingsView: View {
    @AppStorage("dockyard.languageOverride") private var languageOverride: String = ""
    @AppStorage("dockyard.codingCLI") private var codingCLIRaw: String = ""
    @AppStorage("dockyard.tmuxMode") private var tmuxMode: Bool = false
    @AppStorage("dockyard.bypassPermissions") private var bypassPermissions: Bool = false
    @AppStorage("dockyard.allowOutsideWorktree") private var allowOutsideWorktree: Bool = false
    @AppStorage("dockyard.agentTeams") private var agentTeams: Bool = false
    @AppStorage("dockyard.autoRenameBranch") private var autoRenameBranch: Bool = true
    @AppStorage("dockyard.claudePlanTier") private var claudePlanTier: String = ClaudePlanTier.none.rawValue
    @AppStorage("dockyard.defaultTerminal") private var defaultTerminal: String = ""
    @AppStorage("dockyard.defaultBrowser") private var defaultBrowser: String = ""
    @AppStorage("dockyard.branchPrefix") private var branchPrefix: String = "dy"
    @AppStorage("dockyard.useTerminalEditor") private var useTerminalEditor: Bool = false
    @AppStorage("dockyard.terminalEditorCommand") private var terminalEditorCommand: String = "nvim ."
    @AppStorage("dockyard.appearance") private var appearance: String = "system"
    @AppStorage("dockyard.symlinkEnv") private var symlinkEnv: Bool = true
    @AppStorage("dockyard.confirmQuit") private var confirmQuit: Bool = true
    @AppStorage("dockyard.showShortcutHints") private var showShortcutHints: Bool = true
    @AppStorage("dockyard.detailedLogging") private var detailedLogging: Bool = false
    @AppStorage("dockyard.quickActionDebug") private var quickActionDebug: Bool = false
    @AppStorage("dockyard.bleedingEdge") private var bleedingEdge: Bool = false
    @AppStorage("dockyard.baseDirectory") private var baseDirectory: String = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    @EnvironmentObject private var appEnv: AppEnvironment
    @EnvironmentObject private var updater: Updater
    @EnvironmentObject private var shortcutHints: ShortcutHintController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingClearConfirm = false
    #if DEBUG
        private static let cliName = "ff-debug"
    #else
        private static let cliName = "dy"
    #endif
    @State private var cliInstalled = Self.isCliCorrectlyInstalled()

    private var selectedCodingCLI: CodingCLI {
        appEnv.toolStatus.resolvedCodingCLI(storedValue: codingCLIRaw)
    }

    private var codingCLIBinding: Binding<String> {
        Binding(
            get: { selectedCodingCLI.rawValue },
            set: { codingCLIRaw = $0 }
        )
    }

    var body: some View {
        Form {
            // MARK: - Environment

            Section {
                ToolRow(
                    name: "claude",
                    status: appEnv.toolStatus.claude,
                    version: appEnv.toolStatus.claudeVersion
                )
                ToolRow(
                    name: "codex",
                    status: appEnv.toolStatus.codex,
                    version: appEnv.toolStatus.codexVersion
                )
                ToolRow(
                    name: "opencode",
                    status: appEnv.toolStatus.opencode,
                    version: appEnv.toolStatus.opencodeVersion
                )
                ToolRow(
                    name: "gemini",
                    status: appEnv.toolStatus.gemini,
                    version: appEnv.toolStatus.geminiVersion
                )
                ToolRow(
                    name: "gh",
                    status: appEnv.toolStatus.gh,
                    version: appEnv.toolStatus.ghVersion,
                )
                ToolRow(
                    name: "git",
                    status: appEnv.toolStatus.git,
                    version: appEnv.toolStatus.gitVersion
                )
                ToolRow(
                    name: "tmux",
                    status: appEnv.toolStatus.tmux,
                    version: appEnv.toolStatus.tmuxVersion
                )
            } header: {
                HStack {
                    Text("Environment")
                    Spacer()
                    Button(action: { appEnv.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .rotationEffect(.degrees(appEnv.isDetecting ? 360 : 0))
                            .frame(width: 40, height: 40)
                            .animation(appEnv.isDetecting && !reduceMotion ? .linear(duration: 0.8).repeatForever(autoreverses: false) : nil, value: appEnv.isDetecting)
                    }
                    .pressable()
                    .disabled(appEnv.isDetecting)
                }

                LabeledContent(String(format: NSLocalizedString("Install '%@' command", comment: ""), Self.cliName)) {
                    Button(cliInstalled ? "Installed" : "Install...", action: installCLI)
                        .disabled(cliInstalled)
                }
                Text(cliInstalled
                    ? String(format: NSLocalizedString("The '%@' command is installed and ready to use.", comment: ""), Self.cliName)
                    : String(format: NSLocalizedString("Install the '%@' command to open directories in %@ from any terminal.", comment: ""), Self.cliName, AppConstants.appName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - General

            Section("General") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Base directory")
                        Text("Default location when adding new projects.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(baseDirectory.abbreviatedPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Change...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.directoryURL = URL(fileURLWithPath: baseDirectory)
                        panel.message = NSLocalizedString("Choose base directory for projects", comment: "")
                        panel.begin { response in
                            if response == .OK, let url = panel.url {
                                baseDirectory = url.path
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("Branch prefix") {
                        TextField("", text: Binding(
                            get: { branchPrefix },
                            set: { newValue in
                                let filtered = String(newValue.lowercased().filter { $0.isLetter || $0 == "-" })
                                    .replacingOccurrences(of: "--", with: "-")
                                let trimmed = filtered.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                                branchPrefix = trimmed
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 150)
                    }
                    Text("e.g. \(branchPrefix.isEmpty ? "dy" : branchPrefix)/deploy-ludicrous-speed")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                SettingToggle(
                    "Symlink .env files",
                    isOn: $symlinkEnv,
                    description: "Symlink .env and .env.local from the main repository into new worktrees."
                )

                SettingToggle(
                    "Open editor in a terminal",
                    isOn: $useTerminalEditor,
                    description: "Open your editor in a terminal tab (Cmd+O) instead of the built-in editor."
                )

                if useTerminalEditor {
                    VStack(alignment: .leading, spacing: 2) {
                        LabeledContent("Editor command") {
                            TextField("", text: $terminalEditorCommand)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)
                        }
                        Text("Runs in the worktree directory when you open an editor (Cmd+O).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .onChange(of: appearance) { _, newValue in
                    applyAppearance(newValue)
                }

                Picker("Language", selection: $languageOverride) {
                    ForEach(availableLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .onChange(of: languageOverride) { _, newValue in
                    applyLanguage(newValue)
                }

                if !languageOverride.isEmpty {
                    Text("Restart the app for the language change to take effect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingToggle(
                    "Show shortcut hints while holding ⌘",
                    isOn: $showShortcutHints,
                    description: "Display contextual key badges over visible controls when you hold the Command key."
                )
                .onChange(of: showShortcutHints) { _, enabled in
                    shortcutHints.setEnabled(enabled)
                }

                SettingToggle(
                    "Confirm before quitting",
                    isOn: $confirmQuit,
                    description: "Show a confirmation dialog when quitting with active workstreams."
                )

                SettingToggle(
                    "Launch at login",
                    isOn: $launchAtLogin,
                    description: "Automatically open Dockyard when you log in."
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLogin.setEnabled(newValue)
                }
            }

            // MARK: - Updates

            if updater.isConfigured {
                Section("Updates") {
                    SettingToggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                        ),
                        description: "Sparkle checks daily and prompts when a new release is available."
                    )

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check now")
                            Text("Fetches the latest appcast and installs any available update.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Check for Updates...") {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)
                    }
                }
            }

            // MARK: - Coding Agent

            Section("Coding Agent") {
                Picker("Coding CLI", selection: codingCLIBinding) {
                    ForEach(CodingCLI.allCases) { cli in
                        Text(cli.displayName).tag(cli.rawValue)
                    }
                }
                Text("Used as the default for workstreams that have not chosen their own Coding Agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingToggle(
                    "Dangerously skip permissions",
                    isOn: $bypassPermissions,
                    description: "Starts Coding Agents in their full dangerous mode. Claude Code uses bypassPermissions. Codex bypasses approvals and sandboxing. Use only for trusted workstreams.",
                    descriptionStyle: bypassPermissions ? .warning : .secondary
                )

                SettingToggle(
                    "Allow writes outside worktree",
                    isOn: $allowOutsideWorktree,
                    description: bypassPermissions ? "Ignored while dangerous permission mode is on." : "When enabled, the coding agent can modify files anywhere on disk. When disabled, writes are restricted to the worktree directory.",
                    descriptionStyle: allowOutsideWorktree ? .warning : .secondary
                )
                .disabled(bypassPermissions)

                if bypassPermissions, selectedCodingCLI == .opencode || selectedCodingCLI == .gemini {
                    Text("Dangerous permission mode is only wired for Claude Code and Codex.")
                        .font(.caption)
                        .foregroundStyle(DesignColor.statusWarning)
                }

                SettingToggle(
                    "Agent Teams",
                    isOn: $agentTeams,
                    description: "Enables experimental multi-agent coordination. Agents can spawn teammates, delegate tasks, and collaborate across workstreams."
                )
                .disabled(!selectedCodingCLI.supportsAgentTeams)

                if !selectedCodingCLI.supportsAgentTeams {
                    Text("Agent Teams is only available with Claude Code.")
                        .font(.caption)
                        .foregroundStyle(DesignColor.statusWarning)
                }

                SettingToggle(
                    "Auto-rename branch",
                    isOn: $autoRenameBranch,
                    description: "The agent automatically renames the branch to match your current task, updating the tab name and sidebar description."
                )
                .disabled(!selectedCodingCLI.supportsAutoRenameBranch)

                if !selectedCodingCLI.supportsAutoRenameBranch {
                    Text("Auto-rename branch is only available with Claude Code.")
                        .font(.caption)
                        .foregroundStyle(DesignColor.statusWarning)
                }

                Picker("Claude usage plan", selection: $claudePlanTier) {
                    ForEach(ClaudePlanTier.allCases) { tier in
                        Text(tier.displayName).tag(tier.rawValue)
                    }
                }
                Text("Sets your subscription tier so the sidebar usage meter can show an approximate percentage remaining. Consumption is read from local Claude transcripts; limits are estimates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingToggle(
                    "Tmux Mode",
                    isOn: $tmuxMode,
                    description: "Coding Agent sessions persist across app restarts. The Terminal tab is not affected. Sessions are lost on system restart."
                )
                .disabled(!appEnv.toolStatus.tmux.isInstalled)

                if !appEnv.toolStatus.tmux.isInstalled {
                    Text("Requires tmux to be installed.")
                        .font(.caption)
                        .foregroundStyle(DesignColor.statusWarning)
                }

                Picker("External Terminal", selection: $defaultTerminal) {
                    ForEach(appEnv.installedTerminals) { app in
                        Label {
                            Text(app.name)
                        } icon: {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                                    .imageOutline(radius: DesignRadius.xs)
                            }
                        }
                        .tag(app.bundleID)
                    }
                }
                .onAppear {
                    if defaultTerminal.isEmpty, let first = appEnv.installedTerminals.first {
                        defaultTerminal = first.bundleID
                    }
                }

                Picker("External Browser", selection: $defaultBrowser) {
                    Text("System Default").tag("")
                    ForEach(appEnv.installedBrowsers) { app in
                        Label {
                            Text(app.name)
                        } icon: {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous))
                                    .imageOutline(radius: DesignRadius.xs)
                            }
                        }
                        .tag(app.bundleID)
                    }
                }
            }

            // MARK: - Advanced

            Section("Advanced") {
                Toggle(isOn: $detailedLogging) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detailed logging")
                        if detailedLogging {
                            HStack(spacing: 0) {
                                Text("Log setup, run, and teardown script output to files for debugging. ")
                                    .foregroundStyle(.secondary)
                                Button("Open Logs Directory") {
                                    let url = LaunchLogger.logsDirectoryURL
                                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                                    NSWorkspace.shared.open(url)
                                }
                                .pressable()
                                .foregroundStyle(Color.accentColor)
                            }
                            .font(.caption)
                        } else {
                            Text("Log setup, run, and teardown script output to files for debugging.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingToggle(
                    "Quick action debug",
                    isOn: $quickActionDebug,
                    description: "Show a debug panel with command output from quick actions."
                )

                SettingToggle(
                    "Bleeding edge",
                    isOn: $bleedingEdge,
                    description: "Receive pre-release builds with the latest features. These may be less stable.",
                    descriptionStyle: bleedingEdge ? .warning : .secondary
                )

                LabeledContent("Clear project list") {
                    Button("Clear All...", role: .destructive, action: { showingClearConfirm = true })
                        .pressable()
                        .foregroundStyle(DesignColor.statusError)
                }
                Text("Removes all projects and workstreams from the sidebar. No files or directories on disk will be deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Clear project list?", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                NotificationCenter.default.post(name: .clearProjects, object: nil)
            }
        } message: {
            Text("This will remove all projects and workstreams from the sidebar. No files on disk will be deleted. This cannot be undone.")
        }
    }

    private func installCLI() {
        let script = """
        #!/bin/bash
        DIR="${1:-.}"
        RESOLVED=$(cd "$DIR" 2>/dev/null && pwd)
        [ -z "$RESOLVED" ] && echo "Error: directory '$DIR' not found" >&2 && exit 1
        open "\(AppConstants.urlScheme)://$RESOLVED"
        """
        let tempPath = NSTemporaryDirectory() + Self.cliName
        try? script.write(toFile: tempPath, atomically: true, encoding: .utf8)
        chmod(tempPath, 0o755)
        installWithPrivileges(source: tempPath)
    }

    private func installWithPrivileges(source: String) {
        let destination = "/usr/local/bin/\(Self.cliName)"
        let quotedSource = source.replacingOccurrences(of: "'", with: "'\\''")
        let quotedDest = destination.replacingOccurrences(of: "'", with: "'\\''")
        let script = "do shell script \"install -m 755 '\(quotedSource)' '\(quotedDest)'\" with administrator privileges"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error == nil {
                cliInstalled = true
            }
        }
    }

    private func chmod(_ path: String, _ mode: mode_t) {
        Darwin.chmod(path, mode)
    }

    /// Check if the CLI is installed and points to a valid script that opens this app.
    private static func isCliCorrectlyInstalled() -> Bool {
        let path = "/usr/local/bin/\(cliName)"
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              fm.isExecutableFile(atPath: path),
              let contents = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            return false
        }
        return contents.contains(AppConstants.urlScheme)
    }

    private func applyAppearance(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    private var availableLanguages: [(code: String, name: String)] {
        var languages: [(String, String)] = [("", NSLocalizedString("System Default", comment: ""))]
        let bundles = Bundle.main.localizations.filter { $0 != "Base" }.sorted()
        for code in bundles {
            let nativeLocale = Locale(identifier: code)
            let name = nativeLocale.localizedString(forLanguageCode: code) ?? code
            languages.append((code, name.capitalized))
        }
        return languages
    }

    private func applyLanguage(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }
}

// MARK: - Setting Toggle

private enum SettingDescriptionStyle {
    case secondary
    case warning
}

private struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool
    let description: String
    var descriptionStyle: SettingDescriptionStyle

    init(_ title: String, isOn: Binding<Bool>, description: String, descriptionStyle: SettingDescriptionStyle = .secondary) {
        self.title = title
        _isOn = isOn
        self.description = description
        self.descriptionStyle = descriptionStyle
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                Text(LocalizedStringKey(description))
                    .font(.caption)
                    .foregroundStyle(descriptionStyle == .warning ? DesignColor.statusWarning : .secondary)
            }
        }
        .frame(minHeight: 40)
    }
}

// MARK: - Tool Detection

enum BinaryStatus {
    case notFound
    case found(String)

    var isInstalled: Bool {
        if case .found = self { return true }
        return false
    }

    var path: String? {
        if case let .found(p) = self { return p }
        return nil
    }
}

struct ToolStatus {
    var tmux: BinaryStatus = .notFound
    var tmuxVersion: String?
    var claude: BinaryStatus = .notFound
    var claudeVersion: String?
    var claudeSupportsSessionName: Bool = false
    var codex: BinaryStatus = .notFound
    var codexVersion: String?
    var opencode: BinaryStatus = .notFound
    var opencodeVersion: String?
    var gemini: BinaryStatus = .notFound
    var geminiVersion: String?
    var gh: BinaryStatus = .notFound
    var ghVersion: String?
    var git: BinaryStatus = .notFound
    var gitVersion: String?

    static func detect() -> ToolStatus {
        var status = ToolStatus()

        status.tmux = findBinary("tmux")
        if let path = status.tmux.path {
            status.tmuxVersion = runForVersion(path, args: ["-V"])
        }

        status.claude = findBinary("claude")
        if let path = status.claude.path {
            status.claudeVersion = runForVersion(path, args: ["--version"])
            status.claudeSupportsSessionName = helpContainsFlag(path, flag: "--name")
        }

        status.codex = findBinary("codex")
        if let path = status.codex.path {
            status.codexVersion = runForVersion(path, args: ["--version"])
        }

        status.opencode = findBinary("opencode")
        if let path = status.opencode.path {
            status.opencodeVersion = runForVersion(path, args: ["--version"])
        }

        status.gemini = findBinary("gemini")
        if let path = status.gemini.path {
            status.geminiVersion = runForVersion(path, args: ["--version"])
        }

        status.gh = findBinary("gh")
        if let path = status.gh.path {
            status.ghVersion = runForVersion(path, args: ["--version"])
        }

        status.git = findBinary("git")
        if let path = status.git.path {
            status.gitVersion = runForVersion(path, args: ["--version"])
        }

        return status
    }
    private static func findBinary(_ name: String) -> BinaryStatus {
        guard let path = CommandLineTools.path(for: name) else { return .notFound }
        return .found(path)
    }

    private static func runForVersion(_ path: String, args: [String]) -> String? {
        guard let output = runCommand(path, args: args) else { return nil }
        let trimmed = output
            .replacingOccurrences(of: "tmux ", with: "")
            .replacingOccurrences(of: "gh version ", with: "")
            .replacingOccurrences(of: "codex-cli ", with: "")
        return trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
    }

    private static func helpContainsFlag(_ path: String, flag: String) -> Bool {
        guard let output = runCommand(path, args: ["--help"], includeStderr: true) else { return false }
        return output.contains(flag)
    }

    private static func checkGhAuth(_ ghPath: String) -> String? {
        guard let output = runCommand(ghPath, args: ["auth", "status"], includeStderr: true) else {
            return "Not authenticated"
        }
        if let range = output.range(of: "account ") {
            let afterAccount = output[range.upperBound...]
            let username = afterAccount.prefix(while: { !$0.isWhitespace && $0 != "(" })
            if !username.isEmpty {
                return String(username)
            }
        }
        if output.contains("Logged in") {
            return "Authenticated"
        }
        return "Not authenticated"
    }

    private static func runCommand(_ path: String, args: [String], includeStderr: Bool = false) -> String? {
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = includeStderr ? pipe : errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 || includeStderr else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

private struct ToolRow: View {
    let name: String
    let status: BinaryStatus
    var version: String?
    var detail: String?

    var body: some View {
        HStack {
            Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(status.isInstalled ? DesignColor.statusSuccess : .secondary)
                .accessibilityLabel(status.isInstalled ? "Installed" : "Not found")

            Text(name)
                .font(.system(.body, design: .monospaced))

            if let version {
                Text(version)
                    .font(.caption)
                    .tabularNumbers()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if status.isInstalled {
                if let detail {
                    let isAuth = detail != "Not authenticated"
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isAuth ? DesignColor.statusSuccess : DesignColor.statusWarning)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel(isAuth ? "Authenticated" : "Not authenticated")
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - App Detection

struct AppInfo: Identifiable, @unchecked Sendable {
    let name: String
    let bundleID: String
    var id: String {
        bundleID
    }

    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func isAppInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func detectTerminals() -> [AppInfo] {
        let candidates: [(String, String)] = [
            ("Ghostty", "com.mitchellh.ghostty"),
            ("iTerm2", "com.googlecode.iterm2"),
            ("Terminal", "com.apple.Terminal"),
            ("Warp", "dev.warp.Warp-Stable"),
            ("Alacritty", "org.alacritty"),
            ("kitty", "net.kovidgoyal.kitty"),
        ]
        return candidates.compactMap { name, id in
            isAppInstalled(id) ? AppInfo(name: name, bundleID: id) : nil
        }
    }

    static func detectBrowsers() -> [AppInfo] {
        let candidates: [(String, String)] = [
            ("Safari", "com.apple.Safari"),
            ("Google Chrome", "com.google.Chrome"),
            ("Firefox", "org.mozilla.firefox"),
            ("Arc", "company.thebrowser.Browser"),
            ("Brave", "com.brave.Browser"),
            ("Microsoft Edge", "com.microsoft.edgemac"),
            ("Opera", "com.operasoftware.Opera"),
        ]
        return candidates.compactMap { name, id in
            isAppInstalled(id) ? AppInfo(name: name, bundleID: id) : nil
        }
    }
}
