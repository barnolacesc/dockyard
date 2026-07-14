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
