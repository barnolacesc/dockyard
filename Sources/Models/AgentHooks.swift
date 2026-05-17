// ABOUTME: Generates per-workstream claude-settings.json files that wire
// ABOUTME: Claude Code's hooks to the bundled dy-agent-state helper.

import Foundation

enum AgentHooks {
    static var settingsDirectoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("claude-settings", isDirectory: true)
    }

    static func settingsURL(for workstreamID: UUID) -> URL {
        settingsDirectoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
    }

    /// Returns the path Claude Code's `--settings` flag should use for the given
    /// CLI, or nil if the CLI does not support hooks in a way we can target.
    static func settingsPathIfSupported(for cli: CodingCLI, workstreamID: UUID = UUID()) -> URL? {
        switch cli {
        case .claude:
            return settingsURL(for: workstreamID)
        case .codex, .opencode, .gemini:
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
                        "command": "\(quotedHelper) --workstream-id \(id) --state idle",
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

    private static func shellSingleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
