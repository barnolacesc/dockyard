// ABOUTME: Watches dy-run state files and publishes the selected port for a workstream.
// ABOUTME: Uses filesystem events instead of polling so browser targets update immediately.

import Foundation

final class PortDetector: ObservableObject, @unchecked Sendable {
    @Published private(set) var selectedPort: Int?

    private let directoryURL: URL
    private let stateURL: URL
    private let loadState: () -> RunStateSnapshot?
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let recoveryDelay: DispatchTimeInterval
    private let recoveryAttemptLimit: Int
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var recoveryWorkItem: DispatchWorkItem?
    private var remainingRecoveryAttempts = 0
    private var isStopped = false

    init(
        workstreamID: UUID,
        directoryURL: URL = RunStateStore.directoryURL,
        recoveryDelay: DispatchTimeInterval = .milliseconds(50),
        recoveryAttemptLimit: Int = 40,
        loadState: (() -> RunStateSnapshot?)? = nil
    ) {
        self.directoryURL = directoryURL
        self.stateURL = directoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
        self.loadState = loadState ?? { RunStateStore.loadValidated(for: workstreamID) }
        self.queue = DispatchQueue(label: "dockyard.port-detector.\(workstreamID.uuidString.lowercased())")
        self.recoveryDelay = recoveryDelay
        self.recoveryAttemptLimit = recoveryAttemptLimit
        queue.setSpecific(key: queueKey, value: ())
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        queue.sync {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            attachDirectoryWatcher()
            refreshState()
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            queue.sync { stopOnQueue() }
        }
    }

    private func stopOnQueue() {
        isStopped = true
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        remainingRecoveryAttempts = 0
        cancelWatchers()
    }

    private func handleDirectoryEvent() {
        guard let directorySource else { return }
        let event = directorySource.data
        if event.contains(.delete) || event.contains(.rename) {
            cancelWatchers()
            refreshState()
            remainingRecoveryAttempts = recoveryAttemptLimit
            scheduleDirectoryRecovery()
            return
        }

        attachFileWatcherIfNeeded()
        refreshState()
    }

    private func scheduleDirectoryRecovery() {
        guard !isStopped,
              recoveryWorkItem == nil,
              remainingRecoveryAttempts > 0
        else { return }

        remainingRecoveryAttempts -= 1
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.recoveryWorkItem = nil
            guard !self.isStopped else { return }

            self.attachDirectoryWatcher()
            if self.directorySource == nil {
                self.scheduleDirectoryRecovery()
            } else {
                self.remainingRecoveryAttempts = 0
                self.refreshState()
            }
        }
        recoveryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + recoveryDelay, execute: workItem)
    }

    private func handleFileEvent() {
        guard let fileSource else { return }
        let event = fileSource.data
        if event.contains(.delete) || event.contains(.rename) {
            fileSource.cancel()
            self.fileSource = nil
        }
        attachFileWatcherIfNeeded()
        refreshState()
    }

    private func cancelWatchers() {
        fileSource?.cancel()
        fileSource = nil
        directorySource?.cancel()
        directorySource = nil
    }

    private func attachDirectoryWatcher() {
        guard !isStopped, directorySource == nil else { return }

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.attrib, .delete, .extend, .rename, .write],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleDirectoryEvent()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        directorySource = source
        source.resume()

        attachFileWatcherIfNeeded()
    }

    private func attachFileWatcherIfNeeded() {
        guard !isStopped else { return }
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            fileSource?.cancel()
            fileSource = nil
            return
        }
        guard fileSource == nil else { return }

        let descriptor = open(stateURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.attrib, .delete, .extend, .rename, .write],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        fileSource = source
        source.resume()
    }

    private func refreshState() {
        attachFileWatcherIfNeeded()
        let state = loadState()

        let nextPort = state?.selectedPort
        DispatchQueue.main.async { [weak self] in
            self?.selectedPort = nextPort
        }
    }
}
