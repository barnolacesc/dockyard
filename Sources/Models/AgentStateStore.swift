// ABOUTME: Observable singleton that watches agent-state directories
// ABOUTME: with kqueue. Mirrors the pattern used by PortDetector for run-state files.

import Foundation

final class AgentStateStore: ObservableObject, @unchecked Sendable {
    static let shared = AgentStateStore()

    @Published private(set) var states: [UUID: AgentState] = [:]

    private let queue = DispatchQueue(label: "dockyard.agent-state-store")
    private var directorySource: DispatchSourceFileSystemObject?
    let directoryURL: URL

    init(directoryURL: URL = AgentStateFiles.directoryURL) {
        self.directoryURL = directoryURL
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        attachDirectoryWatcher()
        refreshState()
    }

    private func stop() {
        directorySource?.cancel()
        directorySource = nil
    }

    private func attachDirectoryWatcher() {
        let directoryPath = directoryURL.path
        let descriptor = open(directoryPath, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.attrib, .delete, .extend, .rename, .write],
            queue: queue
        )
        
        let handler: @Sendable () -> Void = { [weak self] in
            self?.refreshState()
        }
        source.setEventHandler(handler: handler)
        
        let cancelHandler: @Sendable () -> Void = {
            close(descriptor)
        }
        source.setCancelHandler(handler: cancelHandler)
        
        directorySource = source
        source.resume()
    }

    func agentState(for workstreamID: UUID) -> AgentState? {
        states[workstreamID]
    }

    /// Synchronous rescan of the directory. Tests call this directly so they
    /// do not depend on filesystem-event delivery timing.
    func refresh() {
        refreshState()
    }

    func refreshState() {
        let dirURL = directoryURL
        let next = Self.scanDirectory(at: dirURL)
        DispatchQueue.main.async { [weak self] in
            self?.states = next
        }
    }

    private static func scanDirectory(at dirURL: URL) -> [UUID: AgentState] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [UUID: AgentState] = [:]
        for url in entries where url.pathExtension == "json" {
            let basename = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: basename) else { continue }
            guard let snapshot = Self.loadValidated(from: url) else { continue }
            result[id] = snapshot.state
        }
        return result
    }

    private static func loadValidated(from url: URL) -> AgentStateSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let snapshot = try? decoder.decode(AgentStateSnapshot.self, from: data) else { return nil }
        if RunStateStore.isProcessRunning(pid: snapshot.pid) {
            return snapshot
        }
        return nil
    }
}
