// ABOUTME: Observable singleton that watches ~/Library/Caches/dockyard/agent-state/
// ABOUTME: with kqueue. Mirrors the pattern used by PortDetector for run-state files.

import Foundation


final class AgentStateStore: ObservableObject, @unchecked Sendable {
    static let shared = AgentStateStore()

    @Published private(set) var states: [UUID: AgentState] = [:]

    private let queue = DispatchQueue(label: "dockyard.agent-state-store")
    private var directorySource: DispatchSourceFileSystemObject?

    init() {
        start()
    }

    deinit {
        directorySource?.cancel()
    }

    func agentState(for workstreamID: UUID) -> AgentState? {
        states[workstreamID]
    }

    /// Synchronous rescan of the directory. Tests call this directly so they
    /// do not depend on filesystem-event delivery timing.
    nonisolated func refresh() {
        let next = Self.scanDirectory()
        DispatchQueue.main.async { [weak self] in
            self?.states = next
        }
    }

    private func start() {
        try? FileManager.default.createDirectory(at: AgentStateFiles.directoryURL, withIntermediateDirectories: true)
        attachDirectoryWatcher()
        refresh()
    }

    private func attachDirectoryWatcher() {
        let path = AgentStateFiles.directoryURL.path
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.attrib, .delete, .extend, .rename, .write],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.refresh()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        directorySource = source
        source.resume()
    }

    nonisolated private static func scanDirectory() -> [UUID: AgentState] {
        let dir = AgentStateFiles.directoryURL
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [UUID: AgentState] = [:]
        for url in entries where url.pathExtension == "json" {
            let basename = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: basename) else { continue }
            guard let snapshot = AgentStateFiles.loadValidated(for: id) else { continue }
            result[id] = snapshot.state
        }
        return result
    }
}