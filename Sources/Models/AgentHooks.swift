// ABOUTME: Generates per-workstream agent hook configuration that wires
// ABOUTME: coding agent lifecycle events to the bundled dy-agent-state helper.

import Foundation

struct AgentHookInvocation: Equatable {
    let generatedConfigURL: URL?
    let commandConfigOverrides: [String]
    let commandFlags: [String]
}

enum AgentHooks {
    static var settingsDirectoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("claude-settings", isDirectory: true)
    }

    static func settingsURL(for workstreamID: UUID) -> URL {
        settingsDirectoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
    }

    /// Returns hook invocation data for the given CLI, or nil if the CLI does
    /// not support hooks in a way we can target.
    static func hookInvocation(for cli: CodingCLI, workstreamID: UUID, helperPath: String) throws -> AgentHookInvocation? {
        switch cli {
        case .claude:
            let url = try writeClaudeSettings(workstreamID: workstreamID, helperPath: helperPath)
            return AgentHookInvocation(
                generatedConfigURL: url,
                commandConfigOverrides: [],
                commandFlags: []
            )
        case .codex:
            return codexHookInvocation(workstreamID: workstreamID, helperPath: helperPath)
        case .opencode, .gemini:
            return nil
        }
    }

    /// Writes a fresh `claude-settings.json` for the workstream, embedding the
    /// bundled helper's absolute path and the workstream UUID. Returns the file URL.
    @discardableResult
    static func writeClaudeSettings(workstreamID: UUID, helperPath: String) throws -> URL {
        let id = workstreamID.uuidString.lowercased()
        // Claude runs hook commands via `/bin/sh -c`, so the helper path must
        // be shell-quoted — debug builds live in `Dockyard Debug.app` which
        // contains a space.
        let quotedHelper = shellSingleQuote(helperPath)
        let settings: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [[
                    "hooks": [[
                        "type": "command",
                        "command": "\(quotedHelper) --workstream-id \(id) --state working",
                    ]],
                ]],
                "Notification": [[
                    "hooks": [[
                        "type": "command",
                        "command": "\(quotedHelper) --workstream-id \(id) --state waiting",
                    ]],
                ]],
                "Stop": [[
                    "hooks": [[
                        "type": "command",
                        "command": "\(quotedHelper) --workstream-id \(id) --state idle --chrome-active false",
                    ]],
                ]],
                "PreToolUse": [[
                    "matcher": "mcp__claude-in-chrome__.*",
                    "hooks": [[
                        "type": "command",
                        "command": "\(quotedHelper) --workstream-id \(id) --chrome-active true",
                    ]],
                ]],
                "PostToolUse": [[
                    "matcher": "mcp__claude-in-chrome__.*",
                    "hooks": [[
                        "type": "command",
                        "command": "\(quotedHelper) --workstream-id \(id) --chrome-active false",
                    ]],
                ]],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: settingsDirectoryURL, withIntermediateDirectories: true)
        let url = settingsURL(for: workstreamID)
        try FilePersistence.writeAtomically(data, to: url)
        return url
    }

    /// Path to the bundled helper inside the running app. Returns nil if the
    /// helper is missing (e.g. running unbundled tests).
    static var bundledHelperPath: String? {
        guard let resourceURL = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent() else {
            return nil
        }
        let candidate = resourceURL.appendingPathComponent("Helpers/dy-agent-state").path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    private static func codexHookInvocation(workstreamID: UUID, helperPath: String) -> AgentHookInvocation {
        let id = workstreamID.uuidString.lowercased()
        let quotedHelper = shellSingleQuote(helperPath)
        let eventStates: [(event: String, state: AgentState)] = [
            ("UserPromptSubmit", .working),
            ("PermissionRequest", .waiting),
            ("Stop", .idle),
        ]

        let overrides = eventStates.map { event, state in
            let command = "\(quotedHelper) --workstream-id \(id) --state \(state.rawValue)"
            return codexConfigOverride(event: event, command: command)
        }

        return AgentHookInvocation(
            generatedConfigURL: nil,
            commandConfigOverrides: overrides,
            commandFlags: ["--dangerously-bypass-hook-trust"]
        )
    }

    private static func codexConfigOverride(event: String, command: String) -> String {
        let commandValue = tomlDoubleQuotedString(command)
        return "hooks.\(event)=[{hooks=[{type=\"command\",command=\(commandValue),timeout=10}]}]"
    }

    private static func tomlDoubleQuotedString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                escaped.append("\\\\")
            case "\"":
                escaped.append("\\\"")
            case "\n":
                escaped.append("\\n")
            case "\r":
                escaped.append("\\r")
            case "\t":
                escaped.append("\\t")
            default:
                escaped.append(String(scalar))
            }
        }
        return "\"\(escaped)\""
    }

    private static func shellSingleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
