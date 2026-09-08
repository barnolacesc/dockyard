// ABOUTME: Agent lifecycle state model and on-disk snapshot format.
// ABOUTME: Written by the dy-agent-state helper, read by AgentStateStore.

import Foundation

/// The lifecycle state of a workstream's Coding Agent.
enum AgentState: String, Codable, Equatable {
    /// Agent is processing a turn (most recent hook was UserPromptSubmit).
    case working
    /// Agent is blocked waiting for the user (most recent hook was Notification).
    case waiting
    /// Agent's turn ended (most recent hook was Stop) or process is dead.
    case idle
}

/// On-disk snapshot written by `dy-agent-state` and read by `AgentStateStore`.
struct AgentStateSnapshot: Codable, Equatable {
    let state: AgentState
    let updatedAt: Date
    let pid: Int32
    /// True only while the agent has a Claude in Chrome MCP tool call in flight.
    let chromeActive: Bool

    init(state: AgentState, updatedAt: Date, pid: Int32, chromeActive: Bool = false) {
        self.state = state
        self.updatedAt = updatedAt
        self.pid = pid
        self.chromeActive = chromeActive
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case updatedAt
        case pid
        case chromeActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(AgentState.self, forKey: .state)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pid = try container.decode(Int32.self, forKey: .pid)
        // State files written before Chrome activity tracking did not contain this key.
        chromeActive = try container.decodeIfPresent(Bool.self, forKey: .chromeActive) ?? false
    }
}

/// The bounded lifecycle payload Claude Code sends to SubagentStart and
/// SubagentStop command hooks. No transcript or assistant content is retained.
struct AgentSubagentHookInput: Codable, Equatable {
    // SubagentStop can include the final assistant message. Keep the payload
    // bounded without rejecting normal long-form agent results.
    static let maximumInputBytes = 1024 * 1024
    static let maximumFieldBytes = 128

    let agentID: String
    let agentType: String

    private enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case agentType = "agent_type"
    }

    static func decodeValidated(from data: Data) -> AgentSubagentHookInput? {
        guard !data.isEmpty, data.count <= maximumInputBytes,
              let input = try? JSONDecoder().decode(AgentSubagentHookInput.self, from: data),
              isValidField(input.agentID),
              isValidField(input.agentType)
        else {
            return nil
        }
        return input
    }

    private static func isValidField(_ value: String) -> Bool {
        let bytes = value.utf8.count
        guard bytes > 0, bytes <= maximumFieldBytes else { return false }
        return value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
    }
}

/// One active Claude Code subagent. Separate files avoid lost updates when
/// multiple lifecycle hooks run concurrently.
struct AgentSubagentSnapshot: Codable, Equatable {
    let workstreamID: UUID
    let agentID: String
    let agentType: String
    let updatedAt: Date
    let pid: Int32
}

enum AgentSubagentFiles {
    private static let suffix = ".subagent.json"

    static func isSubagentFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(suffix)
    }

    static func fileURL(
        for workstreamID: UUID,
        agentID: String,
        directoryURL: URL = AgentStateFiles.directoryURL
    ) -> URL? {
        guard agentID.utf8.count > 0,
              agentID.utf8.count <= AgentSubagentHookInput.maximumFieldBytes
        else {
            return nil
        }
        let encodedID = Data(agentID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let filename = "\(workstreamID.uuidString.lowercased())--\(encodedID)\(suffix)"
        return directoryURL.appendingPathComponent(filename)
    }

    static func load(from url: URL) -> AgentSubagentSnapshot? {
        guard isSubagentFile(url),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(AgentSubagentSnapshot.self, from: data),
              let canonicalURL = fileURL(
                  for: snapshot.workstreamID,
                  agentID: snapshot.agentID,
                  directoryURL: url.deletingLastPathComponent()
              ),
              canonicalURL.standardizedFileURL == url.standardizedFileURL
        else {
            return nil
        }
        return snapshot
    }

    static func write(
        _ snapshot: AgentSubagentSnapshot,
        directoryURL: URL = AgentStateFiles.directoryURL
    ) throws {
        guard let url = fileURL(
            for: snapshot.workstreamID,
            agentID: snapshot.agentID,
            directoryURL: directoryURL
        ) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let data = try encoder.encode(snapshot)
        try FilePersistence.writeAtomically(data, to: url)
    }

    static func remove(
        workstreamID: UUID,
        agentID: String,
        directoryURL: URL = AgentStateFiles.directoryURL
    ) throws {
        guard let url = fileURL(
            for: workstreamID,
            agentID: agentID,
            directoryURL: directoryURL
        ) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func removeAll(
        for workstreamID: UUID,
        directoryURL: URL = AgentStateFiles.directoryURL
    ) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let prefix = "\(workstreamID.uuidString.lowercased())--"
        for url in entries where url.lastPathComponent.hasPrefix(prefix) && isSubagentFile(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Static helpers for the on-disk state files. The observable singleton that
/// watches the directory and publishes changes is `AgentStateStore` (added in
/// the next task).
enum AgentStateFiles {
    static var directoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("agent-state", isDirectory: true)
    }

    static func fileURL(for workstreamID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
    }

    static func load(for workstreamID: UUID) -> AgentStateSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: workstreamID)) else { return nil }
        return try? decoder.decode(AgentStateSnapshot.self, from: data)
    }

    /// Returns the snapshot only if the recorded pid is still alive. Stale files
    /// are returned as nil (the indicator shows `unknown`, i.e. no dot).
    static func loadValidated(for workstreamID: UUID) -> AgentStateSnapshot? {
        guard let snapshot = load(for: workstreamID),
              RunStateStore.isProcessRunning(pid: snapshot.pid)
        else {
            return nil
        }
        return snapshot
    }

    static func write(_ snapshot: AgentStateSnapshot, for workstreamID: UUID) throws {
        let data = try encoder.encode(snapshot)
        try FilePersistence.writeAtomically(data, to: fileURL(for: workstreamID))
    }

    static func remove(for workstreamID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: workstreamID))
        AgentSubagentFiles.removeAll(for: workstreamID)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
