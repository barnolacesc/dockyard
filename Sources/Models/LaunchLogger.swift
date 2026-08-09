// ABOUTME: Per-workstream debug log files for agent, run, and setup launches.
// ABOUTME: Writes JSON Lines entries to ~/Library/Caches/dockyard/logs/<workstream-id>.log when detailedLogging is enabled.

import Foundation

struct LaunchLogEntry: Codable {
    struct ToolPaths: Codable {
        let agentCLI: String?
        let claude: String?
        let codex: String?
        let tmux: String?
        let ffRun: String?
    }

    struct Settings: Codable {
        let tmuxMode: Bool
        let bypassPermissions: Bool
        let agentTeams: Bool
        let autoRenameBranch: Bool
        let allowOutsideWorktree: Bool
    }

    let timestamp: String
    let workstreamID: UUID
    let event: String
    let finalCommand: String
    let intermediateCommands: [String]
    let environmentVariables: [String: String]
    let workingDirectory: String
    let toolPaths: ToolPaths
    let settings: Settings
    let shell: String

    init(
        workstreamID: UUID,
        event: String,
        finalCommand: String,
        intermediateCommands: [String],
        environmentVariables: [String: String],
        workingDirectory: String,
        toolPaths: ToolPaths,
        settings: Settings,
        shell: String
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        timestamp = formatter.string(from: Date())
        self.workstreamID = workstreamID
        self.event = event
        self.finalCommand = finalCommand
        self.intermediateCommands = intermediateCommands
        self.environmentVariables = environmentVariables
        self.workingDirectory = workingDirectory
        self.toolPaths = toolPaths
        self.settings = settings
        self.shell = shell
    }
}

enum LaunchLogger {
    private static let privateDirectoryPermissions = 0o700
    private static let privateFilePermissions = 0o600

    static var logsDirectoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    static func logFileURL(for workstreamID: UUID) -> URL {
        logsDirectoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).log")
    }

    /// Append a log entry to the workstream's log file. No-op when detailedLogging is disabled.
    static func log(_ entry: LaunchLogEntry) {
        guard UserDefaults.standard.bool(forKey: "dockyard.detailedLogging") else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"

        let fileManager = FileManager.default
        let dir = logsDirectoryURL
        do {
            try fileManager.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: privateDirectoryPermissions]
            )
            try fileManager.setAttributes(
                [.posixPermissions: privateDirectoryPermissions],
                ofItemAtPath: dir.path
            )

            let fileURL = logFileURL(for: entry.workstreamID)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.setAttributes(
                    [.posixPermissions: privateFilePermissions],
                    ofItemAtPath: fileURL.path
                )
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            } else {
                try Data(line.utf8).write(to: fileURL, options: .atomic)
                try fileManager.setAttributes(
                    [.posixPermissions: privateFilePermissions],
                    ofItemAtPath: fileURL.path
                )
            }
        } catch {}
    }

    /// Delete the log file for a workstream. Called during archive cleanup.
    static func removeLog(for workstreamID: UUID) {
        let fileURL = logFileURL(for: workstreamID)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
