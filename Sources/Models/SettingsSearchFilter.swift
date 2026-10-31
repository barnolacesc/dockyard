// ABOUTME: Search and filtering model for application settings.
// ABOUTME: Case-insensitive search index matching setting titles, options, descriptions, and keywords.

import Foundation

public enum SettingsSectionID: String, CaseIterable, Sendable {
    case environment
    case general
    case power
    case updates
    case codingAgent
    case advanced

    public var title: String {
        switch self {
        case .environment: return "Environment"
        case .general: return "General"
        case .power: return "Power"
        case .updates: return "Updates"
        case .codingAgent: return "Coding Agent"
        case .advanced: return "Advanced"
        }
    }

    public var localizedTitles: [String] {
        switch self {
        case .environment: return ["Environment", "Entorn"]
        case .general: return ["General"]
        case .power: return ["Power", "Energia"]
        case .updates: return ["Updates", "Actualitzacions"]
        case .codingAgent: return ["Coding Agent", "Agent de codi"]
        case .advanced: return ["Advanced", "Avançat"]
        }
    }

    public var keywords: [String] {
        switch self {
        case .environment:
            return ["tools", "binaries", "dependencies", "status", "version", "install", "eines", "estat"]
        case .general:
            return ["preferences", "config", "defaults", "preferències", "configuració"]
        case .power:
            return ["energy", "battery", "sleep", "awake", "caffeinate", "idle", "energia", "repòs", "bateria"]
        case .updates:
            return ["version", "sparkle", "upgrade", "channels", "releases", "actualització", "versions"]
        case .codingAgent:
            return ["agent", "claude", "codex", "opencode", "agy", "pi", "llm", "ai", "cli", "assistant"]
        case .advanced:
            return ["developer", "logs", "debug", "reset", "desenvolupador", "registre", "depuració"]
        }
    }

    public func matches(query: String) -> Bool {
        let allSearchable = localizedTitles + keywords
        return allSearchable.contains { SettingsSearchMatcher.matches(text: $0, query: query) }
    }
}

public enum SettingsItemID: String, CaseIterable, Sendable {
    // MARK: - Environment

    case envToolClaude
    case envToolCodex
    case envToolOpencode
    case envToolAgy
    case envToolPi
    case envToolTerminalBrowser
    case envToolGh
    case envToolGit
    case envToolTmux
    case envInstallCLI

    // MARK: - General

    case generalBaseDirectory
    case generalBranchPrefix
    case generalSymlinkEnv
    case generalEditorCommand
    case generalTheme
    case generalLanguage
    case generalShortcutHints
    case generalConfirmQuit
    case generalLaunchAtLogin

    // MARK: - Power

    case powerKeepAwake

    // MARK: - Updates

    case updatesChannel
    case updatesAutomaticChecks
    case updatesCheckNow

    // MARK: - Coding Agent

    case agentCodingCLI
    case agentDangerousPermissions
    case agentAllowOutsideWorktree
    case agentTeams
    case agentAutoRenameBranch
    case agentClaudeUsagePlan
    case agentTmuxMode
    case agentExternalTerminal
    case agentOpenLinksIn
    case agentExternalBrowser

    // MARK: - Advanced

    case advancedDetailedLogging
    case advancedQuickActionDebug
    case advancedClearProjects
}

public struct SettingsItemDefinition: Sendable {
    public let id: SettingsItemID
    public let section: SettingsSectionID
    public let title: String
    public let description: String
    public let options: [String]
    public let keywords: [String]

    public init(
        id: SettingsItemID,
        section: SettingsSectionID,
        title: String,
        description: String,
        options: [String] = [],
        keywords: [String] = []
    ) {
        self.id = id
        self.section = section
        self.title = title
        self.description = description
        self.options = options
        self.keywords = keywords
    }

    public func matches(query: String) -> Bool {
        let searchableSources = [title, description] + options + keywords
        return searchableSources.contains { SettingsSearchMatcher.matches(text: $0, query: query) }
    }
}

public enum SettingsSearchMatcher {
    public static func matches(text: String, query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        // Direct case- and diacritic-insensitive contains
        if text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }

        // Multi-token match: all whitespace-separated words must appear in text
        let tokens = trimmedQuery.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard tokens.count > 1 else { return false }
        return tokens.allSatisfy { token in
            text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

public enum SettingsSearchRegistry {
    public static let itemsBySection: [SettingsSectionID: [SettingsItemID]] = [
        .environment: [
            .envToolClaude,
            .envToolCodex,
            .envToolOpencode,
            .envToolAgy,
            .envToolPi,
            .envToolTerminalBrowser,
            .envToolGh,
            .envToolGit,
            .envToolTmux,
            .envInstallCLI,
        ],
        .general: [
            .generalBaseDirectory,
            .generalBranchPrefix,
            .generalSymlinkEnv,
            .generalEditorCommand,
            .generalTheme,
            .generalLanguage,
            .generalShortcutHints,
            .generalConfirmQuit,
            .generalLaunchAtLogin,
        ],
        .power: [
            .powerKeepAwake,
        ],
        .updates: [
            .updatesChannel,
            .updatesAutomaticChecks,
            .updatesCheckNow,
        ],
        .codingAgent: [
            .agentCodingCLI,
            .agentDangerousPermissions,
            .agentAllowOutsideWorktree,
            .agentTeams,
            .agentAutoRenameBranch,
            .agentClaudeUsagePlan,
            .agentTmuxMode,
            .agentExternalTerminal,
            .agentOpenLinksIn,
            .agentExternalBrowser,
        ],
        .advanced: [
            .advancedDetailedLogging,
            .advancedQuickActionDebug,
            .advancedClearProjects,
        ],
    ]

    public static func items(for section: SettingsSectionID) -> [SettingsItemID] {
        itemsBySection[section] ?? []
    }

    public static func section(for item: SettingsItemID) -> SettingsSectionID {
        definitions[item]?.section ?? .general
    }

    public static func definition(for item: SettingsItemID) -> SettingsItemDefinition? {
        definitions[item]
    }

    public static let definitions: [SettingsItemID: SettingsItemDefinition] = [
        // MARK: - Environment

        .envToolClaude: SettingsItemDefinition(
            id: .envToolClaude,
            section: .environment,
            title: "claude",
            description: "Anthropic Claude Code CLI tool status and version.",
            options: ["Claude Code", "Anthropic"],
            keywords: ["claude", "anthropic", "agent", "coding cli", "ai", "installed", "status", "version"]
        ),
        .envToolCodex: SettingsItemDefinition(
            id: .envToolCodex,
            section: .environment,
            title: "codex",
            description: "OpenAI Codex CLI tool status and version.",
            options: ["Codex", "OpenAI Codex"],
            keywords: ["codex", "openai", "agent", "coding cli", "ai", "installed", "status", "version"]
        ),
        .envToolOpencode: SettingsItemDefinition(
            id: .envToolOpencode,
            section: .environment,
            title: "opencode",
            description: "OpenCode CLI tool status and version.",
            options: ["OpenCode"],
            keywords: ["opencode", "agent", "coding cli", "ai", "installed", "status", "version"]
        ),
        .envToolAgy: SettingsItemDefinition(
            id: .envToolAgy,
            section: .environment,
            title: "agy",
            description: "Google Antigravity CLI tool status and version.",
            options: ["Antigravity", "Antigravity CLI"],
            keywords: ["agy", "antigravity", "google", "agent", "coding cli", "ai", "installed", "status", "version"]
        ),
        .envToolPi: SettingsItemDefinition(
            id: .envToolPi,
            section: .environment,
            title: "pi",
            description: "Pi Coding Agent CLI tool status and version.",
            options: ["Pi", "Pi Coding Agent"],
            keywords: ["pi", "earendil", "agent", "coding cli", "ai", "installed", "status", "version"]
        ),
        .envToolTerminalBrowser: SettingsItemDefinition(
            id: .envToolTerminalBrowser,
            section: .environment,
            title: "terminal-browser",
            description: "Terminal Browser CLI tool status and version.",
            options: ["Terminal Browser"],
            keywords: ["terminal-browser", "browser", "agent browser", "cli", "installed", "status"]
        ),
        .envToolGh: SettingsItemDefinition(
            id: .envToolGh,
            section: .environment,
            title: "gh",
            description: "GitHub command line tool status, version, and authentication.",
            options: ["GitHub CLI", "gh"],
            keywords: ["gh", "github", "pr", "issue", "auth", "cli", "installed", "status"]
        ),
        .envToolGit: SettingsItemDefinition(
            id: .envToolGit,
            section: .environment,
            title: "git",
            description: "Git version control tool status and version.",
            options: ["Git"],
            keywords: ["git", "version control", "worktree", "branch", "vcs", "installed", "status"]
        ),
        .envToolTmux: SettingsItemDefinition(
            id: .envToolTmux,
            section: .environment,
            title: "tmux",
            description: "Terminal multiplexer status and version.",
            options: ["tmux"],
            keywords: ["tmux", "multiplexer", "terminal", "sessions", "installed", "status"]
        ),
        .envInstallCLI: SettingsItemDefinition(
            id: .envInstallCLI,
            section: .environment,
            title: "Install command",
            description: "Install the command-line launcher (dy or ff-debug) to open directories in Dockyard from any terminal.",
            options: ["Install...", "Installed", "Instal·la...", "Instal·lat"],
            keywords: ["install", "cli", "dy", "ff-debug", "launcher", "terminal", "command", "path", "open directories", "comanda"]
        ),

        // MARK: - General

        .generalBaseDirectory: SettingsItemDefinition(
            id: .generalBaseDirectory,
            section: .general,
            title: "Base directory",
            description: "Default location when adding new projects.",
            options: ["Change...", "Canvia...", "Choose base directory for projects"],
            keywords: ["base directory", "directori base", "folder", "projects path", "location", "default directory", "browse", "ubicació"]
        ),
        .generalBranchPrefix: SettingsItemDefinition(
            id: .generalBranchPrefix,
            section: .general,
            title: "Branch prefix",
            description: "Prefix added to automatically generated git branches (e.g. dy/deploy-ludicrous-speed).",
            options: ["dy"],
            keywords: ["branch prefix", "prefix de branca", "git", "branch", "naming", "prefix", "branca"]
        ),
        .generalSymlinkEnv: SettingsItemDefinition(
            id: .generalSymlinkEnv,
            section: .general,
            title: "Symlink .env files",
            description: "Symlink .env and .env.local from the main repository into new worktrees.",
            options: [".env", ".env.local"],
            keywords: ["symlink", "env", "environment variables", "dotenv", "local", "worktrees", "fitxers .env", "variables d'entorn"]
        ),
        .generalEditorCommand: SettingsItemDefinition(
            id: .generalEditorCommand,
            section: .general,
            title: "Editor command",
            description: "Runs in the worktree directory when you open an editor (Cmd+O).",
            options: ["nvim .", "code", "vim"],
            keywords: ["editor command", "comanda de l'editor", "editor", "nvim", "vim", "code", "cmd+o", "open editor", "ide"]
        ),
        .generalTheme: SettingsItemDefinition(
            id: .generalTheme,
            section: .general,
            title: "Theme",
            description: "Application appearance and color scheme.",
            options: ["System", "Light", "Dark", "Sistema", "Clar", "Fosc"],
            keywords: ["theme", "tema", "appearance", "light", "dark", "system", "color mode", "dark mode", "light mode", "aparença"]
        ),
        .generalLanguage: SettingsItemDefinition(
            id: .generalLanguage,
            section: .general,
            title: "Language",
            description: "Interface language override. Restart the app for the language change to take effect.",
            options: ["System Default", "English", "Català", "Spanish", "Español"],
            keywords: ["language", "idioma", "localization", "locale", "catalan", "english", "restart", "translation", "traducció"]
        ),
        .generalShortcutHints: SettingsItemDefinition(
            id: .generalShortcutHints,
            section: .general,
            title: "Show shortcut hints while holding ⌘",
            description: "Display contextual key badges over visible controls when you hold the Command key.",
            options: ["⌘", "Command"],
            keywords: ["shortcut hints", "dreceres", "keyboard shortcuts", "command key", "badges", "keys", "hints", "pistes"]
        ),
        .generalConfirmQuit: SettingsItemDefinition(
            id: .generalConfirmQuit,
            section: .general,
            title: "Confirm before quitting",
            description: "Show a confirmation dialog when quitting with active workstreams.",
            options: ["Confirm", "Quit"],
            keywords: ["confirm before quitting", "confirmar abans de sortir", "quit", "exit", "prompt", "dialog", "workstreams", "warning", "sortir"]
        ),
        .generalLaunchAtLogin: SettingsItemDefinition(
            id: .generalLaunchAtLogin,
            section: .general,
            title: "Launch at login",
            description: "Automatically open Dockyard when you log in.",
            options: ["Auto-start", "Login item"],
            keywords: ["launch at login", "iniciar en iniciar sessió", "startup", "boot", "login", "auto start", "obertura automàtica"]
        ),

        // MARK: - Power

        .powerKeepAwake: SettingsItemDefinition(
            id: .powerKeepAwake,
            section: .power,
            title: "Keep Mac awake",
            description: "Prevents idle system sleep while Dockyard is open. The display can still turn off.",
            options: ["Off", "While workstreams are running", "While Coding Agents Work", "Always", "Desactivat", "Sempre", "Mentre treballen els agents de codi"],
            keywords: ["caffeinate", "keep mac awake", "mantén el mac despert", "sleep", "awake", "power", "battery", "idle", "energy", "repòs", "despert"]
        ),

        // MARK: - Updates

        .updatesChannel: SettingsItemDefinition(
            id: .updatesChannel,
            section: .updates,
            title: "Release channel",
            description: "Select between stable releases or pre-release builds with preview features.",
            options: ["Stable releases", "Pre-releases", "Stable", "Pre-release"],
            keywords: ["release channel", "canal de llançament", "updates", "channel", "stable", "pre-releases", "beta", "preview", "releases", "actualitzacions"]
        ),
        .updatesAutomaticChecks: SettingsItemDefinition(
            id: .updatesAutomaticChecks,
            section: .updates,
            title: "Automatically check for updates",
            description: "Sparkle checks daily and prompts when a new release is available.",
            options: ["Sparkle", "Daily"],
            keywords: ["automatically check for updates", "comprova actualitzacions automàticament", "sparkle", "auto update", "daily check", "prompt", "notification"]
        ),
        .updatesCheckNow: SettingsItemDefinition(
            id: .updatesCheckNow,
            section: .updates,
            title: "Check now",
            description: "Checks origin for updates according to your selected release channel or appcast.",
            options: ["Check for Updates...", "Comprova si hi ha actualitzacions..."],
            keywords: ["check now", "comprova ara", "check for updates", "update check", "fetch", "latest version"]
        ),

        // MARK: - Coding Agent

        .agentCodingCLI: SettingsItemDefinition(
            id: .agentCodingCLI,
            section: .codingAgent,
            title: "Coding CLI",
            description: "Used as the default for workstreams that have not chosen their own Coding Agent.",
            options: ["Claude Code", "OpenAI Codex", "Antigravity", "OpenCode", "Pi"],
            keywords: ["coding cli", "cli de codi", "coding agent", "default agent", "claude", "codex", "opencode", "agy", "pi", "provider", "llm", "ai"]
        ),
        .agentDangerousPermissions: SettingsItemDefinition(
            id: .agentDangerousPermissions,
            section: .codingAgent,
            title: "Dangerously skip permissions",
            description: "Starts Coding Agents in their full dangerous mode. Claude Code uses bypassPermissions. Codex bypasses approvals and sandboxing. Use only for trusted workstreams.",
            options: ["Bypass permissions", "Full dangerous mode"],
            keywords: ["dangerously skip permissions", "omiteix permisos perillosament", "bypass", "bypasspermissions", "permissions", "permisos", "dangerous mode", "approvals", "sandboxing", "skip"]
        ),
        .agentAllowOutsideWorktree: SettingsItemDefinition(
            id: .agentAllowOutsideWorktree,
            section: .codingAgent,
            title: "Allow writes outside worktree",
            description: "When enabled, the coding agent can modify files anywhere on disk. When disabled, writes are restricted to the worktree directory. Ignored while dangerous permission mode is on.",
            options: ["Worktree restriction", "Filesystem writes"],
            keywords: ["allow writes outside worktree", "permet escriptures fora del worktree", "worktree", "writes", "restrict", "outside", "filesystem", "modify files", "sandbox", "directory", "system prompt", "bypass", "permissions"]
        ),
        .agentTeams: SettingsItemDefinition(
            id: .agentTeams,
            section: .codingAgent,
            title: "Agent Teams",
            description: "Enables experimental multi-agent coordination. Agents can spawn teammates, delegate tasks, and collaborate across workstreams. Available with Claude Code.",
            options: ["Multi-agent", "Teammates"],
            keywords: ["agent teams", "equips d'agents", "teams", "multi-agent", "swarm", "teammates", "delegate", "collaborate", "coordination"]
        ),
        .agentAutoRenameBranch: SettingsItemDefinition(
            id: .agentAutoRenameBranch,
            section: .codingAgent,
            title: "Auto-rename branch",
            description: "The agent automatically renames the branch to match your current task, updating the tab name and sidebar description.",
            options: ["Branch renaming", "Task naming"],
            keywords: ["auto-rename branch", "canvia el nom de la branca automàticament", "auto rename", "branch", "prompt", "rename branch", "task name", "system prompt", "git branch"]
        ),
        .agentClaudeUsagePlan: SettingsItemDefinition(
            id: .agentClaudeUsagePlan,
            section: .codingAgent,
            title: "Claude usage plan",
            description: "Sets your subscription tier so the sidebar usage meter can show an approximate percentage remaining. Consumption is read from local Claude transcripts.",
            options: ["None", "Pro", "Team", "Enterprise"],
            keywords: ["claude usage plan", "pla d'ús de claude", "usage plan", "subscription tier", "usage meter", "tier", "pro", "team", "enterprise", "quota", "limits", "rate limit"]
        ),
        .agentTmuxMode: SettingsItemDefinition(
            id: .agentTmuxMode,
            section: .codingAgent,
            title: "Tmux Mode",
            description: "Coding Agent sessions persist across app restarts. The Terminal tab is not affected. Sessions are lost on system restart. Requires tmux to be installed.",
            options: ["Persistent sessions", "tmux"],
            keywords: ["tmux mode", "mode tmux", "tmux", "persist", "restarts", "sessions", "background", "multiplexer"]
        ),
        .agentExternalTerminal: SettingsItemDefinition(
            id: .agentExternalTerminal,
            section: .codingAgent,
            title: "External Terminal",
            description: "Choose external terminal application launched with Cmd+Option+T.",
            options: ["Ghostty", "iTerm2", "Terminal", "Warp", "Alacritty", "kitty"],
            keywords: ["external terminal", "terminal extern", "terminal app", "ghostty", "iterm", "warp", "alacritty", "kitty", "cmd+option+t"]
        ),
        .agentOpenLinksIn: SettingsItemDefinition(
            id: .agentOpenLinksIn,
            section: .codingAgent,
            title: "Open links in",
            description: "Where links clicked in the Coding Agent, terminal, and browser tabs should open.",
            options: ["External Browser", "Internal Tab", "In-App Browser", "Ask Each Time", "Navegador extern", "Navegador integrat"],
            keywords: ["open links in", "obre els enllaços a", "links", "urls", "external browser", "internal tab", "in-app browser", "target", "click"]
        ),
        .agentExternalBrowser: SettingsItemDefinition(
            id: .agentExternalBrowser,
            section: .codingAgent,
            title: "External Browser",
            description: "Default browser for opening external links (Cmd+Option+B).",
            options: ["System Default", "Safari", "Google Chrome", "Firefox", "Arc", "Brave", "Microsoft Edge", "Opera"],
            keywords: ["external browser", "navegador extern", "default browser", "safari", "chrome", "firefox", "arc", "brave", "edge", "opera", "web browser"]
        ),

        // MARK: - Advanced

        .advancedDetailedLogging: SettingsItemDefinition(
            id: .advancedDetailedLogging,
            section: .advanced,
            title: "Detailed logging",
            description: "Log setup, run, and teardown script output to files for debugging.",
            options: ["Open Logs Directory", "Obre el directori de registres"],
            keywords: ["detailed logging", "registre detallat", "logging", "logs", "debug", "scripts", "stdout", "stderr", "output", "files"]
        ),
        .advancedQuickActionDebug: SettingsItemDefinition(
            id: .advancedQuickActionDebug,
            section: .advanced,
            title: "Quick action debug",
            description: "Show a debug panel with command output from quick actions.",
            options: ["Debug panel"],
            keywords: ["quick action debug", "depuració d'accions ràpides", "quick actions", "debug panel", "output", "git commands"]
        ),
        .advancedClearProjects: SettingsItemDefinition(
            id: .advancedClearProjects,
            section: .advanced,
            title: "Clear project list",
            description: "Removes all projects and workstreams from the sidebar. No files or directories on disk will be deleted.",
            options: ["Clear All...", "Clear All", "Cancel", "Esborra-ho tot..."],
            keywords: ["clear project list", "esborra la llista de projectes", "clear all", "reset", "remove projects", "wipe", "delete project list", "clean sidebar"]
        ),
    ]
}

public struct SettingsFilter: Equatable, Sendable {
    public var query: String = ""

    public init(query: String = "") {
        self.query = query
    }

    public var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func matches(section: SettingsSectionID) -> Bool {
        guard isSearching else { return true }
        if section.matches(query: query) {
            return true
        }
        let items = SettingsSearchRegistry.items(for: section)
        return items.contains { matches(item: $0) }
    }

    public func matches(item: SettingsItemID) -> Bool {
        guard isSearching else { return true }
        let section = SettingsSearchRegistry.section(for: item)
        if section.matches(query: query) {
            return true
        }
        guard let definition = SettingsSearchRegistry.definition(for: item) else {
            return false
        }
        return definition.matches(query: query)
    }

    public var hasMatches: Bool {
        guard isSearching else { return true }
        return SettingsSectionID.allCases.contains { matches(section: $0) }
    }
}
