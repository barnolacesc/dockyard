// ABOUTME: Observable singleton that watches agent-state directories
// ABOUTME: with kqueue. Mirrors the pattern used by PortDetector for run-state files.

import Foundation

final class AgentStateStore: ObservableObject, @unchecked Sendable {
    static let shared = AgentStateStore()
    private static let privateDirectoryPermissions = 0o700

    @Published private(set) var states: [UUID: AgentState] = [:]
    @Published private(set) var chromeActiveWorkstreamIDs = Set<UUID>()
    @Published private(set) var activeSubagentCounts: [UUID: Int] = [:]

    private let queue = DispatchQueue(label: "dockyard.agent-state-store")
    private var directorySource: DispatchSourceFileSystemObject?
    private var refreshTimer: DispatchSourceTimer?
    let directoryURL: URL

    init(directoryURL: URL = AgentStateFiles.directoryURL) {
        self.directoryURL = directoryURL
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        attachDirectoryWatcher()
        attachRefreshTimer()
        refreshState()
    }

    private func stop() {
        directorySource?.cancel()
        directorySource = nil
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    private func attachDirectoryWatcher() {
        guard directorySource == nil else { return }
        guard prepareStateDirectory() else { return }

        let directoryPath = directoryURL.path
        let descriptor = open(directoryPath, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.attrib, .delete, .extend, .rename, .write],
            queue: queue
        )

        let handler: @Sendable () -> Void = { [weak self] in
            self?.handleDirectoryEvent()
        }
        source.setEventHandler(handler: handler)

        let cancelHandler: @Sendable () -> Void = {
            close(descriptor)
        }
        source.setCancelHandler(handler: cancelHandler)

        directorySource = source
        source.resume()
    }

    private func prepareStateDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.privateDirectoryPermissions]
            )
            // Existing directories retain their previous mode after createDirectory.
            try FileManager.default.setAttributes(
                [.posixPermissions: Self.privateDirectoryPermissions],
                ofItemAtPath: directoryURL.path
            )
            return true
        } catch {
            return false
        }
    }

    private func handleDirectoryEvent() {
        guard let directorySource else { return }
        let event = directorySource.data
        if event.contains(.delete) || event.contains(.rename) {
            replaceDirectoryWatcher()
            return
        }
        refreshState()
    }

    private func replaceDirectoryWatcher() {
        directorySource?.cancel()
        directorySource = nil
        attachDirectoryWatcher()
        refreshState()
    }

    private func attachRefreshTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.directorySource == nil {
                self.replaceDirectoryWatcher()
            } else {
                self.refreshState()
            }
        }
        refreshTimer = timer
        timer.resume()
    }

    func agentState(for workstreamID: UUID) -> AgentState? {
        states[workstreamID]
    }

    func isChromeActive(for workstreamID: UUID) -> Bool {
        chromeActiveWorkstreamIDs.contains(workstreamID)
    }

    func activeSubagentCount(for workstreamID: UUID) -> Int {
        activeSubagentCounts[workstreamID, default: 0]
    }

    /// Synchronous rescan of the directory. Tests call this directly so they
    /// do not depend on filesystem-event delivery timing.
    func refresh() {
        refreshState()
    }

    func refreshState() {
        let dirURL = directoryURL
        let next = Self.scanDirectory(at: dirURL, now: Date())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.states != next.states {
                self.states = next.states
            }
            if self.chromeActiveWorkstreamIDs != next.chromeActiveWorkstreamIDs {
                self.chromeActiveWorkstreamIDs = next.chromeActiveWorkstreamIDs
            }
            if self.activeSubagentCounts != next.activeSubagentCounts {
                self.activeSubagentCounts = next.activeSubagentCounts
            }
        }
    }

    private struct ScannedState {
        var states: [UUID: AgentState] = [:]
        var chromeActiveWorkstreamIDs = Set<UUID>()
        var activeSubagentCounts: [UUID: Int] = [:]
    }

    private static func scanDirectory(at dirURL: URL, now: Date) -> ScannedState {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
            return ScannedState()
        }
        var result = ScannedState()
        for url in entries where url.pathExtension == "json" {
            if AgentSubagentFiles.isSubagentFile(url) {
                guard let snapshot = AgentSubagentFiles.load(from: url),
                      RunStateStore.isProcessRunning(pid: snapshot.pid)
                else {
                    continue
                }
                result.activeSubagentCounts[snapshot.workstreamID, default: 0] += 1
                continue
            }
            let basename = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: basename) else { continue }
            guard let snapshot = Self.loadValidated(from: url) else { continue }
            result.states[id] = Self.decayedState(snapshot, now: now)
            if snapshot.chromeActive {
                result.chromeActiveWorkstreamIDs.insert(id)
            }
        }
        for (workstreamID, count) in result.activeSubagentCounts where count > 0 {
            if result.states[workstreamID] != .waiting {
                result.states[workstreamID] = .working
            }
        }
        return result
    }

    static func decayedState(_ snapshot: AgentStateSnapshot, now: Date) -> AgentState {
        let age = now.timeIntervalSince(snapshot.updatedAt)
        switch snapshot.state {
        case .working where age > 30 * 60:
            return .idle
        case .waiting where age > 2 * 60 * 60:
            return .idle
        case .working, .waiting, .idle:
            return snapshot.state
        }
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
