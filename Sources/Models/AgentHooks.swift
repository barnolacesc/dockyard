// ABOUTME: Generates per-workstream agent hook configuration that wires
// ABOUTME: coding agent lifecycle events to the bundled dy-agent-state helper.

import Foundation

struct AgentHookInvocation: Equatable {
    let generatedConfigURL: URL?
    let commandConfigOverrides: [String]
    let commandFlags: [String]
}

enum AgentHookError: LocalizedError, Equatable {
    case hooksFileCorrupted
    case hookCollision(String)

    var errorDescription: String? {
        switch self {
        case .hooksFileCorrupted:
            return "The .agents/hooks.json file is corrupted or not a valid JSON object."
        case let .hookCollision(key):
            return "A hook named '\(key)' already exists and is not managed by Dockyard."
        }
    }
}

enum AgentHooks {
    static var settingsDirectoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("claude-settings", isDirectory: true)
    }

    static var openCodeSettingsDirectoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("opencode-settings", isDirectory: true)
    }

    static func settingsURL(for workstreamID: UUID) -> URL {
        settingsDirectoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
    }

    /// Creates an OpenCode-only instruction file outside the worktree and
    /// returns inline config content suitable for `OPENCODE_CONFIG_CONTENT`.
    /// Inline configuration has the right precedence without modifying the
    /// project's own OpenCode configuration or AGENTS.md.
    static func openCodeAutoRenameConfiguration(workstreamID: UUID) throws -> String {
        let directory = openCodeSettingsDirectoryURL
            .appendingPathComponent(workstreamID.uuidString.lowercased(), isDirectory: true)
        let instructionsURL = directory.appendingPathComponent("auto-rename.md")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FilePersistence.writeAtomically(Data(SystemPrompts.autoRenameBranchPrompt.utf8), to: instructionsURL)

        let config: [String: Any] = ["instructions": [instructionsURL.path]]
        let data = try JSONSerialization.data(withJSONObject: config)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return content
    }

    /// Returns hook invocation data for the given CLI, or nil if the CLI does
    /// not support hooks in a way we can target.
    static func hookInvocation(
        for cli: CodingCLI,
        workstreamID: UUID,
        helperPath: String,
        workingDirectory: String? = nil
    ) throws -> AgentHookInvocation? {
        switch cli.capabilities.stateReportingStrategy {
        case .claudeHooks:
            let url = try writeClaudeSettings(workstreamID: workstreamID, helperPath: helperPath)
            return AgentHookInvocation(
                generatedConfigURL: url,
                commandConfigOverrides: [],
                commandFlags: []
            )
        case .codexHooks:
            return codexHookInvocation(workstreamID: workstreamID, helperPath: helperPath)
        case .agyHooks:
            guard let workingDirectory else { return nil }
            guard let url = try writeAgyHooks(workingDirectory: workingDirectory, workstreamID: workstreamID, helperPath: helperPath) else {
                return nil
            }
            return AgentHookInvocation(
                generatedConfigURL: url,
                commandConfigOverrides: [],
                commandFlags: []
            )
        case .unavailable:
            return nil
        }
    }

    /// Writes `<workingDirectory>/.agents/hooks.json` for the workstream,
    /// embedding the bundled helper's absolute path and the workstream UUID.
    /// Preserves any existing non-dockyard hooks. Returns the file URL,
    /// or `nil` if the file is tracked by git and should not be mutated.
    @discardableResult
    static func writeAgyHooks(workingDirectory: String, workstreamID: UUID, helperPath: String) throws -> URL? {
        if isTrackedByGit(workingDirectory: workingDirectory, relativePath: ".agents/hooks.json") {
            return nil
        }

        let id = workstreamID.uuidString.lowercased()
        let quotedHelper = shellSingleQuote(helperPath)

        let agentsDir = URL(fileURLWithPath: workingDirectory).appendingPathComponent(".agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let hooksURL = agentsDir.appendingPathComponent("hooks.json")

        var existingHooks: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            let data = try Data(contentsOf: hooksURL)
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let json = jsonObject as? [String: Any] else {
                throw AgentHookError.hooksFileCorrupted
            }
            existingHooks = json
        }

        if let existing = existingHooks["dockyard-state"] {
            guard isDockyardManagedHook(existing) else {
                throw AgentHookError.hookCollision("dockyard-state")
            }
        }

        let dockyardHooks: [String: Any] = [
            "PreInvocation": [
                [
                    "type": "command",
                    "command": "\(quotedHelper) --workstream-id \(id) --state working",
                ],
            ],
            "PreToolUse": [
                [
                    "matcher": "ask_question",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(quotedHelper) --workstream-id \(id) --state waiting",
                        ],
                    ],
                ],
            ],
            "PostToolUse": [
                [
                    "matcher": "ask_question",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(quotedHelper) --workstream-id \(id) --state working",
                        ],
                    ],
                ],
            ],
            "Stop": [
                [
                    "type": "command",
                    "command": "\(quotedHelper) --workstream-id \(id) --state idle",
                ],
            ],
        ]

        existingHooks["dockyard-state"] = dockyardHooks

        let data = try JSONSerialization.data(withJSONObject: existingHooks, options: [.prettyPrinted, .sortedKeys])
        try FilePersistence.writeAtomically(data, to: hooksURL)

        excludeFromGitIfPossible(workingDirectory: workingDirectory, relativePath: ".agents/hooks.json")

        return hooksURL
    }

    /// Removes the `dockyard-state` hook entry from `<workingDirectory>/.agents/hooks.json`.
    /// If no other hooks remain, deletes `hooks.json`.
    static func removeAgyHooks(workingDirectory: String) {
        if isTrackedByGit(workingDirectory: workingDirectory, relativePath: ".agents/hooks.json") {
            return
        }

        let hooksURL = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent(".agents", isDirectory: true)
            .appendingPathComponent("hooks.json")
        guard FileManager.default.fileExists(atPath: hooksURL.path),
              let data = try? Data(contentsOf: hooksURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let existing = json["dockyard-state"],
              isDockyardManagedHook(existing)
        else { return }

        json.removeValue(forKey: "dockyard-state")
        if json.isEmpty {
            try? FileManager.default.removeItem(at: hooksURL)
        } else if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? FilePersistence.writeAtomically(updatedData, to: hooksURL)
        }
    }

    static func isDockyardManagedHook(_ hookValue: Any) -> Bool {
        guard let hookDict = hookValue as? [String: Any] else { return false }
        guard let data = try? JSONSerialization.data(withJSONObject: hookDict),
              let string = String(data: data, encoding: .utf8)
        else {
            return false
        }
        return string.contains("dy-agent-state")
    }

    static func isTrackedByGit(workingDirectory: String, relativePath: String) -> Bool {
        guard let gitPath = CommandLineTools.path(for: "git") else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["ls-files", "--error-unmatch", "--", relativePath]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func excludeFromGitIfPossible(workingDirectory: String, relativePath: String) {
        if isTrackedByGit(workingDirectory: workingDirectory, relativePath: relativePath) {
            return
        }
        guard let gitPath = CommandLineTools.path(for: "git") else { return }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["rev-parse", "--git-path", "info/exclude"]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let rawPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawPath.isEmpty else { return }

            let excludeURL: URL
            if rawPath.hasPrefix("/") {
                excludeURL = URL(fileURLWithPath: rawPath)
            } else {
                excludeURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent(rawPath)
            }

            var content = ""
            if let existingData = try? Data(contentsOf: excludeURL),
               let existing = String(data: existingData, encoding: .utf8)
            {
                content = existing
            }

            let lines = content.components(separatedBy: .newlines)
            if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == relativePath }) {
                let prefix = content.isEmpty || content.hasSuffix("\n") ? "" : "\n"
                let updated = content + prefix + "\(relativePath)\n"
                try FileManager.default.createDirectory(at: excludeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FilePersistence.writeAtomically(Data(updated.utf8), to: excludeURL)
            }
        } catch {
            // Best effort; ignore failure if git exclude cannot be updated.
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
                "SubagentStart": [[
                    "hooks": [[
                        "type": "command",
                        "command": "\(quotedHelper) --workstream-id \(id) --subagent-event start",
                    ]],
                ]],
                "SubagentStop": [[
                    "hooks": [[
                        "type": "command",
                        "command": "\(quotedHelper) --workstream-id \(id) --subagent-event stop",
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
