// ABOUTME: Read-only bridge that exposes the embedded WKWebView's state to the agent.
// ABOUTME: Writes per-workstream JSON (current URL, title, recent console logs) to the cache directory.

import Foundation
import OSLog

private let logger = Logger(subsystem: "dockyard", category: "browser-bridge")

@MainActor
enum BrowserBridge {
    static let envVarName = "DOCKYARD_BROWSER_STATE_FILE"

    static var stateDirectory: URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = cache.appendingPathComponent(AppConstants.appID).appendingPathComponent("browser-state")
        do {
            try prepareStateDirectory(at: dir)
        } catch {
            logger.warning("[BrowserBridge] failed to secure state directory: \(error.localizedDescription, privacy: .public)")
        }
        return dir
    }

    static func stateFile(for workstreamID: UUID) -> URL {
        stateDirectory.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
    }

    struct State: Codable {
        var url: String?
        var title: String?
        var updatedAt: Date
        var consoleLog: [LogEntry]

        struct LogEntry: Codable {
            var level: String
            var message: String
            var timestamp: Date
        }
    }

    /// Write the current state for a given workstream. Best-effort; failures are logged.
    static func write(workstreamID: UUID, url: String?, title: String?, appendLog: State.LogEntry? = nil) {
        let file = stateFile(for: workstreamID)
        var state = read(workstreamID: workstreamID) ?? State(url: nil, title: nil, updatedAt: Date(), consoleLog: [])
        state.url = url
        state.title = title
        state.updatedAt = Date()
        if let appendLog {
            state.consoleLog.append(appendLog)
            // Keep at most 200 entries so the file doesn't grow unbounded.
            if state.consoleLog.count > 200 {
                state.consoleLog.removeFirst(state.consoleLog.count - 200)
            }
        }

        do {
            try persist(state, to: file)
        } catch {
            logger.warning("[BrowserBridge] failed to write state: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func read(workstreamID: UUID) -> State? {
        try? decodeState(at: stateFile(for: workstreamID))
    }

    static func persist(_ state: State, to file: URL) throws {
        try prepareStateDirectory(at: file.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FilePersistence.writeAtomically(encoder.encode(state), to: file)
    }

    static func decodeState(at file: URL) throws -> State {
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(State.self, from: data)
    }

    private static func prepareStateDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Existing directories retain their previous mode after createDirectory.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    static func clear(workstreamID: UUID) {
        try? FileManager.default.removeItem(at: stateFile(for: workstreamID))
    }
}
