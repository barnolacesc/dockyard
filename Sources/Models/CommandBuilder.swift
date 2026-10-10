// ABOUTME: Builds shell command strings with proper escaping.
// ABOUTME: Replaces ad-hoc string concatenation for claude/tmux commands.

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct CommandBuilder {
    private var parts: [String] = []

    init(_ executable: String) {
        parts.append(executable)
    }

    mutating func arg(_ value: String) {
        parts.append(value)
    }

    mutating func flag(_ name: String) {
        parts.append(name)
    }

    mutating func option(_ name: String, _ value: String) {
        parts.append(name)
        parts.append(Self.shellQuote(value))
    }

    mutating func quotedArg(_ value: String) {
        parts.append(Self.shellQuote(value))
    }

    var command: String {
        parts.joined(separator: " ")
    }

    static func loginCommand(_ command: String, shell: String = userShell) -> String {
        let shCommand = "exec /bin/sh -c \(shellQuote(command, forShell: shell))"
        return "\(shell) -lic \(shellQuote(shCommand, forShell: shell))"
    }

    /// Wrap two commands in a fallback using the user's login shell for proper PATH.
    /// Uses two layers: the login shell loads profiles, then exec's sh for POSIX syntax.
    /// This is shell-agnostic (works with zsh, bash, fish) because only sh sees POSIX operators.
    static func withFallback(_ primary: String, _ fallback: String, message: String? = nil, shell: String = userShell) -> String {
        let fallbackCmd: String
        if let message {
            let escapedMessage = shellQuote(message)
            fallbackCmd = "(echo \(escapedMessage); \(fallback))"
        } else {
            fallbackCmd = fallback
        }
        let posixCmd = "\(primary) || \(fallbackCmd)"
        let shArgQuote = isFish(shell) ? fishQuote(posixCmd) : shellQuote(posixCmd)
        let shCmd = "exec sh -c \(shArgQuote)"
        return "\(shell) -lic \(shellQuote(shCmd, forShell: shell))"
    }

    static var userShell: String {
        resolvedUserShell()
    }

    static func resolvedUserShell(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        if let shell = environment["SHELL"], !shell.isEmpty, isExecutable(shell) {
            return shell
        }

        for fallback in ["/bin/zsh", "/bin/bash", "/bin/sh"] where isExecutable(fallback) {
            return fallback
        }

        return "/bin/sh"
    }

    static func shellQuote(_ s: String) -> String {
        let simple = !s.isEmpty && s.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." || $0 == "/" || $0 == ":" || $0 == "~" || $0 == "@" || $0 == "+" || $0 == "="
        }
        if simple { return s }
        return "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// Quote a string for the given shell. Fish 4.0 can't parse POSIX '\'' escaping,
    /// so we use double quotes when Fish is the outer shell.
    static func shellQuote(_ s: String, forShell shell: String) -> String {
        let simple = !s.isEmpty && s.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." || $0 == "/" || $0 == ":" || $0 == "~" || $0 == "@" || $0 == "+" || $0 == "="
        }
        if simple { return s }
        if isFish(shell) {
            return fishQuote(s)
        }
        return shellQuote(s)
    }

    static func isFish(_ shell: String) -> Bool {
        shell.hasSuffix("/fish") || shell == "fish"
    }

    private static func fishQuote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        return "\"\(escaped)\""
    }
}

enum CodingCLI: String, CaseIterable, Identifiable {
    case claude
    case codex
    case opencode
    case agy

    var id: String {
        rawValue
    }

    var commandName: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .claude:
            return NSLocalizedString("Claude Code", comment: "")
        case .codex:
            return NSLocalizedString("Codex", comment: "")
        case .opencode:
            return NSLocalizedString("OpenCode", comment: "")
        case .agy:
            return NSLocalizedString("Antigravity CLI", comment: "")
        }
    }

    var installURL: URL {
        switch self {
        case .claude:
            return URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!
        case .codex:
            return URL(string: "https://developers.openai.com/codex")!
        case .opencode:
            return URL(string: "https://github.com/opencode")!
        case .agy:
            return URL(string: "https://antigravity.google")!
        }
    }

    var missingTitle: String {
        switch self {
        case .claude:
            return NSLocalizedString("Claude Code not found", comment: "")
        case .codex:
            return NSLocalizedString("Codex not found", comment: "")
        case .opencode:
            return NSLocalizedString("OpenCode not found", comment: "")
        case .agy:
            return NSLocalizedString("Antigravity CLI not found", comment: "")
        }
    }

    var missingDescription: String {
        switch self {
        case .claude:
            return NSLocalizedString("Install Claude Code to use the Coding Agent.", comment: "")
        case .codex:
            return NSLocalizedString("Install Codex to use the Coding Agent.", comment: "")
        case .opencode:
            return NSLocalizedString("Install OpenCode to use the Coding Agent.", comment: "")
        case .agy:
            return NSLocalizedString("Install Antigravity CLI to use the Coding Agent.", comment: "")
        }
    }

    var installLabel: String {
        switch self {
        case .claude:
            return NSLocalizedString("Install Claude Code", comment: "")
        case .codex:
            return NSLocalizedString("Install Codex", comment: "")
        case .opencode:
            return NSLocalizedString("Install OpenCode", comment: "")
        case .agy:
            return NSLocalizedString("Install Antigravity CLI", comment: "")
        }
    }
}

func effectiveCodingCLIRaw(workstream: String?, global: String) -> String {
    guard let workstream, !workstream.isEmpty else { return global }
    return workstream
}

extension ToolStatus {
    func status(for cli: CodingCLI) -> BinaryStatus {
        switch cli {
        case .claude:
            return claude
        case .codex:
            return codex
        case .opencode:
            return opencode
        case .agy:
            return agy
        }
    }

    func version(for cli: CodingCLI) -> String? {
        switch cli {
        case .claude:
            return claudeVersion
        case .codex:
            return codexVersion
        case .opencode:
            return opencodeVersion
        case .agy:
            return agyVersion
        }
    }

    func path(for cli: CodingCLI) -> String? {
        status(for: cli).path
    }

    func supportsSessionName(for cli: CodingCLI) -> Bool {
        switch cli {
        case .claude:
            return claudeSupportsSessionName
        case .codex, .opencode, .agy:
            return false
        }
    }

    func resolvedCodingCLI(storedValue: String) -> CodingCLI {
        let normalized = storedValue == "gemini" ? CodingCLI.agy.rawValue : storedValue
        if let selected = CodingCLI(rawValue: normalized), !normalized.isEmpty {
            return selected
        }
        if claude.isInstalled {
            return .claude
        }
        if opencode.isInstalled {
            return .opencode
        }
        if agy.isInstalled {
            return .agy
        }
        if codex.isInstalled {
            return .codex
        }
        return .claude
    }
}

struct AgentLaunchCommand {
    let finalCommand: String
    let intermediateCommands: [String]
}

enum CodingCLICommandBuilder {
    static func buildAgentCommand(
        cli: CodingCLI,
        cliPath: String,
        workingDirectory: String,
        projectName: String,
        workstreamName: String,
        sessionName: String? = nil,
        workstreamID: UUID,
        tmuxPath: String?,
        useTmux: Bool,
        bypassPermissions: Bool,
        allowOutsideWorktree: Bool,
        autoRenameBranch: Bool,
        envVars: [String: String],
        supportsSessionName: Bool,
        hookInvocation: AgentHookInvocation? = nil,
        terminalBrowserPath: String? = nil,
        browserURL: String? = nil,
        initialPrompt: String? = nil
    ) -> AgentLaunchCommand {
        var command: AgentLaunchCommand
        switch cli.capabilities.commandStrategy {
        case .claude:
            command = buildClaudeAgentCommand(
                cliPath: cliPath,
                workingDirectory: workingDirectory,
                sessionName: sessionName ?? workstreamName,
                workstreamID: workstreamID,
                useTmux: useTmux,
                bypassPermissions: bypassPermissions,
                allowOutsideWorktree: allowOutsideWorktree,
                autoRenameBranch: autoRenameBranch,
                supportsSessionName: supportsSessionName,
                settingsPath: hookInvocation?.generatedConfigURL,
                terminalBrowserPath: terminalBrowserPath,
                browserURL: browserURL,
                initialPrompt: initialPrompt
            )
        case .codex:
            command = buildCodexAgentCommand(
                cliPath: cliPath,
                workingDirectory: workingDirectory,
                workstreamID: workstreamID,
                bypassPermissions: bypassPermissions,
                allowOutsideWorktree: allowOutsideWorktree,
                autoRenameBranch: autoRenameBranch,
                hookInvocation: hookInvocation,
                terminalBrowserPath: terminalBrowserPath,
                browserURL: browserURL,
                initialPrompt: initialPrompt
            )
        case .agy:
            command = buildAgyAgentCommand(
                cliPath: cliPath,
                workingDirectory: workingDirectory,
                bypassPermissions: bypassPermissions,
                initialPrompt: initialPrompt
            )
        case .generic:
            command = buildGenericAgentCommand(
                cli: cli,
                cliPath: cliPath,
                workingDirectory: workingDirectory,
                initialPrompt: initialPrompt
            )
        }

        if cli != .codex || hookInvocation?.sessionHelperPath == nil, let initialPrompt, !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let continuation = buildAgentCommand(
                cli: cli,
                cliPath: cliPath,
                workingDirectory: workingDirectory,
                projectName: projectName,
                workstreamName: workstreamName,
                sessionName: sessionName,
                workstreamID: workstreamID,
                tmuxPath: nil,
                useTmux: useTmux,
                bypassPermissions: bypassPermissions,
                allowOutsideWorktree: allowOutsideWorktree,
                autoRenameBranch: autoRenameBranch,
                envVars: envVars,
                supportsSessionName: supportsSessionName,
                hookInvocation: hookInvocation,
                terminalBrowserPath: terminalBrowserPath,
                browserURL: browserURL
            )
            command = AgentLaunchCommand(
                finalCommand: AgentInitialPrompt.wrap(
                    command: command.finalCommand,
                    continuation: continuation.finalCommand,
                    receiptURL: AgentInitialPrompt.receiptURL(for: workstreamID)
                ),
                intermediateCommands: command.intermediateCommands
            )
        }

        if useTmux, cli.capabilities.supportsDockyardTmuxPersistence, let tmuxPath {
            let session = cli == .codex
                ? TmuxSession.codexSessionName(workstreamID: workstreamID)
                : TmuxSession.sessionName(project: projectName, workstream: workstreamName, role: "agent")
            let wrapped = TmuxSession.wrapCommand(
                tmuxPath: tmuxPath,
                sessionName: session,
                command: command.finalCommand,
                environmentVars: envVars,
                respawnOnExit: true
            )
            return AgentLaunchCommand(
                finalCommand: wrapped,
                intermediateCommands: command.intermediateCommands + [wrapped]
            )
        }

        return command
    }

    private static func buildClaudeAgentCommand(
        cliPath: String,
        workingDirectory: String,
        sessionName: String,
        workstreamID: UUID,
        useTmux: Bool,
        bypassPermissions: Bool,
        allowOutsideWorktree: Bool,
        autoRenameBranch: Bool,
        supportsSessionName: Bool,
        settingsPath: URL?,
        terminalBrowserPath: String?,
        browserURL: String?,
        initialPrompt: String? = nil
    ) -> AgentLaunchCommand {
        let sessionID = workstreamID.uuidString.lowercased()

        var systemPromptParts: [String] = []
        if !allowOutsideWorktree {
            systemPromptParts.append(SystemPrompts.restrictToWorktreePrompt(worktreePath: workingDirectory))
        }
        if autoRenameBranch {
            systemPromptParts.append(SystemPrompts.autoRenameBranchPrompt)
        }
        if let terminalBrowserPath, let browserURL {
            systemPromptParts.append(SystemPrompts.terminalBrowserPrompt(
                executablePath: terminalBrowserPath,
                previewURL: browserURL
            ))
        }
        let combinedSystemPrompt = systemPromptParts.isEmpty ? nil : systemPromptParts.joined(separator: "\n\n")

        var resume = CommandBuilder(cliPath)
        resume.option("--resume", sessionID)
        if supportsSessionName {
            resume.option("--name", sessionName)
        }
        if useTmux {
            resume.flag("--teammate-mode")
            resume.arg("tmux")
        }
        applyClaudePermissionOptions(to: &resume, bypassPermissions: bypassPermissions)
        if let combinedSystemPrompt {
            resume.option("--append-system-prompt", combinedSystemPrompt)
        }
        if let settingsPath {
            resume.option("--settings", settingsPath.path)
        }

        var fresh = CommandBuilder(cliPath)
        fresh.option("--session-id", sessionID)
        if supportsSessionName {
            fresh.option("--name", sessionName)
        }
        if useTmux {
            fresh.flag("--teammate-mode")
            fresh.arg("tmux")
        }
        applyClaudePermissionOptions(to: &fresh, bypassPermissions: bypassPermissions)
        if let combinedSystemPrompt {
            fresh.option("--append-system-prompt", combinedSystemPrompt)
        }
        if let settingsPath {
            fresh.option("--settings", settingsPath.path)
        }

        let normalizedPrompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedPrompt, !normalizedPrompt.isEmpty {
            resume.quotedArg(normalizedPrompt)
            fresh.quotedArg(normalizedPrompt)
        }

        let finalCommand = CommandBuilder.withFallback(
            resume.command,
            fresh.command,
            message: NSLocalizedString("Starting new session...", comment: "")
        )
        return AgentLaunchCommand(
            finalCommand: finalCommand,
            intermediateCommands: [resume.command, fresh.command, finalCommand]
        )
    }

    private static func buildCodexAgentCommand(
        cliPath: String,
        workingDirectory: String,
        workstreamID: UUID,
        bypassPermissions: Bool,
        allowOutsideWorktree: Bool,
        autoRenameBranch: Bool,
        hookInvocation: AgentHookInvocation?,
        terminalBrowserPath: String?,
        browserURL: String?,
        initialPrompt: String? = nil
    ) -> AgentLaunchCommand {
        var resume = CommandBuilder(cliPath)
        resume.arg("resume")
        resume.arg("\"$dockyard_codex_thread\"")
        resume.flag("--no-daemon")
        applyCodexInteractiveOptions(
            to: &resume,
            workingDirectory: workingDirectory,
            bypassPermissions: bypassPermissions,
            allowOutsideWorktree: allowOutsideWorktree
        )
        applyCodexInstructions(
            to: &resume,
            autoRenameBranch: autoRenameBranch,
            terminalBrowserPath: terminalBrowserPath,
            browserURL: browserURL
        )
        applyCodexHookOptions(to: &resume, hookInvocation: hookInvocation)

        var fresh = CommandBuilder(cliPath)
        fresh.flag("--no-daemon")
        applyCodexInteractiveOptions(
            to: &fresh,
            workingDirectory: workingDirectory,
            bypassPermissions: bypassPermissions,
            allowOutsideWorktree: allowOutsideWorktree
        )
        applyCodexInstructions(
            to: &fresh,
            autoRenameBranch: autoRenameBranch,
            terminalBrowserPath: terminalBrowserPath,
            browserURL: browserURL
        )
        applyCodexHookOptions(to: &fresh, hookInvocation: hookInvocation)

        guard let helperPath = hookInvocation?.sessionHelperPath else {
            if let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                fresh.quotedArg(prompt)
            }
            return AgentLaunchCommand(finalCommand: CommandBuilder.loginCommand(fresh.command), intermediateCommands: [fresh.command])
        }
        let finalCommand = CodexSession.wrap(
            fresh: fresh.command, resume: resume.command, helperPath: helperPath,
            workstreamID: workstreamID, workingDirectory: workingDirectory, initialPrompt: initialPrompt
        )
        return AgentLaunchCommand(finalCommand: finalCommand, intermediateCommands: [resume.command, fresh.command])
    }

    /// Checks Antigravity CLI's SQLite metadata store (`conversation_summaries.db`) to determine
    /// if a conversation has already been recorded for the given working directory.
    ///
    /// - Parameters:
    ///   - workingDirectory: The filesystem path of the workspace / worktree.
    ///   - dbPath: Optional custom path to `conversation_summaries.db` (used for testing).
    /// - Returns: `true` if a matching conversation exists for this workspace; `false` otherwise.
    static func hasExistingAgyConversation(
        workingDirectory: String,
        dbPath: String? = nil
    ) -> Bool {
        let path = dbPath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/conversation_summaries.db").path
        guard FileManager.default.fileExists(atPath: path) else { return false }

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_close(db) }

        let standardPath = (workingDirectory as NSString).standardizingPath
        var targetURI = URL(fileURLWithPath: standardPath).absoluteString
        while targetURI.hasSuffix("/") {
            targetURI.removeLast()
        }

        let query = "SELECT 1 FROM conversation_summaries WHERE workspace_uris LIKE ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(targetURI)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)

        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Builds the launch command for Antigravity CLI (`agy`).
    ///
    /// If an existing conversation is detected for `workingDirectory`, attempts `agy --continue`
    /// with fallback to a fresh session. If no conversation exists for the workspace, launches
    /// fresh directly without `--continue` to avoid traversing up to `$HOME` and capturing stale sessions.
    ///
    /// - Parameters:
    ///   - cliPath: Absolute path to the `agy` binary.
    ///   - workingDirectory: The filesystem path of the workspace.
    ///   - bypassPermissions: Whether to auto-approve tool execution (`--dangerously-skip-permissions`).
    ///   - hasExistingConversation: Explicit override for whether an existing conversation exists (for testing).
    ///   - initialPrompt: Optional initial prompt to autofill into interactive session.
    /// - Returns: An `AgentLaunchCommand` configured for direct launch or continuation with fallback.
    static func buildAgyAgentCommand(
        cliPath: String,
        workingDirectory: String,
        bypassPermissions: Bool,
        hasExistingConversation: Bool? = nil,
        initialPrompt: String? = nil
    ) -> AgentLaunchCommand {
        let shouldResume = hasExistingConversation ?? hasExistingAgyConversation(workingDirectory: workingDirectory)
        let normalizedPrompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldResume {
            var resume = CommandBuilder(cliPath)
            resume.flag("--continue")
            applyAgyPermissionOptions(to: &resume, bypassPermissions: bypassPermissions)
            if let normalizedPrompt, !normalizedPrompt.isEmpty {
                resume.option("--prompt-interactive", normalizedPrompt)
            }

            var fresh = CommandBuilder(cliPath)
            applyAgyPermissionOptions(to: &fresh, bypassPermissions: bypassPermissions)
            if let normalizedPrompt, !normalizedPrompt.isEmpty {
                fresh.option("--prompt-interactive", normalizedPrompt)
            }

            let finalCommand = CommandBuilder.withFallback(
                resume.command,
                fresh.command,
                message: NSLocalizedString("Starting new session...", comment: "")
            )
            return AgentLaunchCommand(
                finalCommand: finalCommand,
                intermediateCommands: [resume.command, fresh.command, finalCommand]
            )
        } else {
            var command = CommandBuilder(cliPath)
            applyAgyPermissionOptions(to: &command, bypassPermissions: bypassPermissions)
            if let normalizedPrompt, !normalizedPrompt.isEmpty {
                command.option("--prompt-interactive", normalizedPrompt)
            }

            return AgentLaunchCommand(
                finalCommand: command.command,
                intermediateCommands: [command.command]
            )
        }
    }

    private static func applyAgyPermissionOptions(
        to command: inout CommandBuilder,
        bypassPermissions: Bool
    ) {
        if bypassPermissions {
            command.flag("--dangerously-skip-permissions")
        }
    }

    private static func buildGenericAgentCommand(
        cli: CodingCLI,
        cliPath: String,
        workingDirectory _: String,
        initialPrompt: String? = nil
    ) -> AgentLaunchCommand {
        var fresh = CommandBuilder(cliPath)
        let normalizedPrompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if cli == .opencode, let normalizedPrompt, !normalizedPrompt.isEmpty {
            fresh.option("--prompt", normalizedPrompt)
        }

        return AgentLaunchCommand(
            finalCommand: fresh.command,
            intermediateCommands: [fresh.command]
        )
    }

    private static func applyCodexInteractiveOptions(
        to command: inout CommandBuilder,
        workingDirectory: String,
        bypassPermissions: Bool,
        allowOutsideWorktree: Bool
    ) {
        command.option("-C", workingDirectory)
        applyCodexPermissionOptions(
            to: &command,
            bypassPermissions: bypassPermissions,
            allowOutsideWorktree: allowOutsideWorktree
        )
    }

    private static func applyClaudePermissionOptions(
        to command: inout CommandBuilder,
        bypassPermissions: Bool
    ) {
        if bypassPermissions {
            command.option("--permission-mode", "bypassPermissions")
        } else {
            command.flag("--allow-dangerously-skip-permissions")
        }
    }

    private static func applyCodexPermissionOptions(
        to command: inout CommandBuilder,
        bypassPermissions: Bool,
        allowOutsideWorktree: Bool
    ) {
        if bypassPermissions {
            command.flag("--dangerously-bypass-approvals-and-sandbox")
        } else {
            command.option("--sandbox", allowOutsideWorktree ? "danger-full-access" : "workspace-write")
            command.option("--ask-for-approval", "on-request")
        }
    }

    private static func applyCodexHookOptions(
        to command: inout CommandBuilder,
        hookInvocation: AgentHookInvocation?
    ) {
        guard let hookInvocation else { return }

        for override in hookInvocation.commandConfigOverrides {
            command.option("--config", override)
        }
        for flag in hookInvocation.commandFlags {
            command.flag(flag)
        }
    }

    /// Codex accepts a per-invocation TOML configuration override. This keeps
    /// Dockyard's instructions scoped to its own agent session rather than
    /// changing the user's global Codex configuration.
    private static func applyCodexInstructions(
        to command: inout CommandBuilder,
        autoRenameBranch: Bool,
        terminalBrowserPath: String?,
        browserURL: String?
    ) {
        var instructions: [String] = []
        if autoRenameBranch {
            instructions.append(SystemPrompts.autoRenameBranchPrompt)
        }
        if let terminalBrowserPath, let browserURL {
            instructions.append(SystemPrompts.terminalBrowserPrompt(
                executablePath: terminalBrowserPath,
                previewURL: browserURL
            ))
        }
        guard !instructions.isEmpty else { return }
        command.option(
            "--config",
            "developer_instructions=\(tomlBasicString(instructions.joined(separator: "\n\n")))"
        )
    }

    private static func tomlBasicString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped.append("\\\\")
            case "\"": escaped.append("\\\"")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            default: escaped.append(String(scalar))
            }
        }
        return "\"\(escaped)\""
    }
}

extension CodexSession {
    static func wrap(fresh: String, resume: String, helperPath: String, workstreamID: UUID,
                     workingDirectory: String, initialPrompt: String?, directory: URL = AppConstants.configDirectory, shell: String = CommandBuilder.userShell) -> String
    {
        let quote: (String) -> String = { CommandBuilder.shellQuote($0) }
        let helper = "\(quote(helperPath)) --workstream-id \(workstreamID.uuidString.lowercased()) --working-directory \(quote(workingDirectory)) --codex-config-directory \(quote(directory.path))"
        let receipt = quote(AgentInitialPrompt.receiptURL(for: workstreamID, directory: directory).path)
        let stateDirectory = quote(fileURL(for: workstreamID, directory: directory).deletingLastPathComponent().path)
        let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let script = """
        [ -d \(quote(workingDirectory)) ] || exit 1
        mkdir -p \(stateDirectory) || exit $?
        DOCKYARD_CODEX_START_RECEIPT=$(mktemp \(stateDirectory)/launch.XXXXXX) || exit $?
        export DOCKYARD_CODEX_START_RECEIPT
        trap 'rm -f "$DOCKYARD_CODEX_START_RECEIPT"' EXIT
        unset DOCKYARD_CODEX_INITIAL_PROMPT
        if [ ! -f \(receipt) ] && [ -n \(quote(prompt)) ]; then
          DOCKYARD_CODEX_INITIAL_PROMPT=\(quote(prompt))
          export DOCKYARD_CODEX_INITIAL_PROMPT
        fi
        dockyard_codex_thread=$(\(helper) --codex-resolve) || exit $?
        \(helper) --codex-register-process || exit $?
        dockyard_codex_run() {
          if [ -n "${DOCKYARD_CODEX_INITIAL_PROMPT:-}" ]; then
            "$@" "$DOCKYARD_CODEX_INITIAL_PROMPT"
          else
            "$@"
          fi
        }
        if [ -n "$dockyard_codex_thread" ]; then
          dockyard_codex_run \(resume)
          dockyard_codex_status=$?
          if [ "$dockyard_codex_status" -eq 0 ] || [ -s "$DOCKYARD_CODEX_START_RECEIPT" ]; then
            exit "$dockyard_codex_status"
          fi
          if [ "$dockyard_codex_status" -gt 128 ] || [ "$dockyard_codex_status" -eq 126 ] || [ "$dockyard_codex_status" -eq 127 ]; then
            exit "$dockyard_codex_status"
          fi
        fi
        dockyard_codex_run \(fresh)
        dockyard_fresh_status=$?
        if [ -n "$dockyard_codex_thread" ]; then
          if [ "$dockyard_fresh_status" -eq 0 ] && [ ! -s "$DOCKYARD_CODEX_START_RECEIPT" ]; then
            \(helper) --codex-clear || exit $?
          fi
        fi
        exit "$dockyard_fresh_status"
        """
        return CommandBuilder.loginCommand(script, shell: shell)
    }
}
