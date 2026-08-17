// ABOUTME: Declares the versioned, truthful capability contract for each Coding Agent CLI.
// ABOUTME: Keeps launch, persistence, state, and permission UI gates from drifting apart.

enum CodingAgentCommandStrategy: Equatable {
    case claude
    case codex
    case generic
}

enum CodingAgentStateReportingStrategy: Equatable {
    case claudeHooks
    case codexHooks
    case unavailable
}

struct CodingAgentCapabilities: Equatable {
    static let contractVersion = 1

    let commandStrategy: CodingAgentCommandStrategy
    let stateReportingStrategy: CodingAgentStateReportingStrategy
    let supportsDirectLaunch: Bool
    let supportsCLISessionResume: Bool
    let supportsDockyardTmuxPersistence: Bool
    let reportsMainAgentState: Bool
    let reportsSubagentState: Bool
    let supportsDangerousPermissionBypass: Bool
    let supportsLivePermissionControl: Bool
    let supportsAutoRenameBranch: Bool
    let supportsAgentTeams: Bool
}

extension CodingCLI {
    var capabilities: CodingAgentCapabilities {
        switch self {
        case .claude:
            return CodingAgentCapabilities(
                commandStrategy: .claude,
                stateReportingStrategy: .claudeHooks,
                supportsDirectLaunch: true,
                supportsCLISessionResume: true,
                supportsDockyardTmuxPersistence: true,
                reportsMainAgentState: true,
                reportsSubagentState: false,
                supportsDangerousPermissionBypass: true,
                supportsLivePermissionControl: true,
                supportsAutoRenameBranch: true,
                supportsAgentTeams: true
            )
        case .codex:
            return CodingAgentCapabilities(
                commandStrategy: .codex,
                stateReportingStrategy: .codexHooks,
                supportsDirectLaunch: true,
                supportsCLISessionResume: true,
                supportsDockyardTmuxPersistence: true,
                reportsMainAgentState: true,
                reportsSubagentState: false,
                supportsDangerousPermissionBypass: true,
                supportsLivePermissionControl: true,
                supportsAutoRenameBranch: false,
                supportsAgentTeams: false
            )
        case .opencode, .gemini:
            return CodingAgentCapabilities(
                commandStrategy: .generic,
                stateReportingStrategy: .unavailable,
                supportsDirectLaunch: true,
                supportsCLISessionResume: false,
                supportsDockyardTmuxPersistence: true,
                reportsMainAgentState: false,
                reportsSubagentState: false,
                supportsDangerousPermissionBypass: false,
                supportsLivePermissionControl: false,
                supportsAutoRenameBranch: false,
                supportsAgentTeams: false
            )
        }
    }

    var supportsAgentTeams: Bool {
        capabilities.supportsAgentTeams
    }

    var supportsAutoRenameBranch: Bool {
        capabilities.supportsAutoRenameBranch
    }
}
