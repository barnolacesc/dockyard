// ABOUTME: Shared run-state types for dy-run and the app-side port monitor.
// ABOUTME: Encodes detected localhost ports, selection rules, and state-file persistence.

import Darwin
import Foundation

enum RunStateStatus: String, Codable {
    case starting
    case running
    case stopped
    case crashed
}

struct RunStateSnapshot: Codable {
    let workstreamID: UUID
    let pid: Int32
    let status: RunStateStatus
    let detectedPorts: [Int]
    let selectedPort: Int?
    let startedAt: Date
}

struct PortSelectionResult {
    let detectedPorts: [Int]
    let selectedPort: Int?
}

struct PortSelectionTracker {
    let expectedPort: Int?
    private var lastCandidate: Int?
    private var candidateMatches = 0
    private(set) var selectedPort: Int?

    init(expectedPort: Int?) {
        self.expectedPort = expectedPort
    }

    mutating func update(listeningPorts: Set<Int>) -> PortSelectionResult {
        let currentPorts = Set(listeningPorts.filter { $0 > 0 })

        if let selectedPort, !currentPorts.contains(selectedPort) {
            self.selectedPort = nil
        }

        let candidate = candidatePort(currentPorts: currentPorts)

        if selectedPort == nil,
           let candidate
        {
            if candidate == lastCandidate {
                candidateMatches += 1
            } else {
                lastCandidate = candidate
                candidateMatches = 1
            }
            if candidateMatches >= 2 {
                selectedPort = candidate
            }
        } else if selectedPort == nil {
            lastCandidate = nil
            candidateMatches = 0
        }

        return PortSelectionResult(
            detectedPorts: orderedPorts(currentPorts, preferredPort: selectedPort ?? candidate),
            selectedPort: selectedPort
        )
    }

    private func candidatePort(currentPorts: Set<Int>) -> Int? {
        if currentPorts.count == 1, let onlyPort = currentPorts.first {
            return onlyPort
        }
        if currentPorts.count > 1,
           let expectedPort,
           currentPorts.contains(expectedPort)
        {
            return expectedPort
        }
        return nil
    }

    private func orderedPorts(_ currentPorts: Set<Int>, preferredPort: Int?) -> [Int] {
        let sortedPorts = currentPorts.sorted()
        guard let preferredPort,
              currentPorts.contains(preferredPort),
              currentPorts.count > 1
        else {
            return sortedPorts
        }

        return [preferredPort] + sortedPorts.filter { $0 != preferredPort }
    }
}

enum RunStateStore {
    static let maximumSnapshotBytes = 1_048_576

    static var directoryURL: URL {
        AppConstants.cacheDirectory.appendingPathComponent("run-state", isDirectory: true)
    }

    static func fileURL(for workstreamID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
    }

    static func load(for workstreamID: UUID) -> RunStateSnapshot? {
        load(from: fileURL(for: workstreamID))
    }

    static func loadValidated(for workstreamID: UUID) -> RunStateSnapshot? {
        guard let state = load(for: workstreamID),
              state.workstreamID == workstreamID,
              state.status == .starting || state.status == .running,
              isProcessRunning(pid: state.pid),
              processStartedNearSnapshot(pid: state.pid, recordedStart: state.startedAt)
        else {
            return nil
        }
        return state
    }

    static func load(from url: URL) -> RunStateSnapshot? {
        guard let data = readBoundedRegularFile(at: url) else { return nil }
        return try? decoder.decode(RunStateSnapshot.self, from: data)
    }

    static func write(_ state: RunStateSnapshot, for workstreamID: UUID) throws {
        let data = try encoder.encode(state)
        try FilePersistence.writeAtomically(data, to: fileURL(for: workstreamID))
    }

    static func remove(for workstreamID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: workstreamID))
    }

    static func isProcessRunning(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    static func processStartDate(pid: Int32) -> Date? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let actualSize = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, expectedSize)
        }
        guard actualSize == expectedSize else { return nil }

        let seconds = TimeInterval(info.pbi_start_tvsec)
        let microseconds = TimeInterval(info.pbi_start_tvusec) / 1_000_000
        return Date(timeIntervalSince1970: seconds + microseconds)
    }

    private static func processStartedNearSnapshot(pid: Int32, recordedStart: Date) -> Bool {
        guard let processStart = processStartDate(pid: pid) else { return false }
        // dy-run records its timestamp immediately after spawning the monitor.
        // A reused PID points to a process with a materially different birth time.
        return abs(recordedStart.timeIntervalSince(processStart)) <= 5
    }

    private static func readBoundedRegularFile(at url: URL) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size >= 0,
              metadata.st_size <= off_t(maximumSnapshotBytes)
        else {
            return nil
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))

        do {
            while data.count <= maximumSnapshotBytes {
                let remaining = maximumSnapshotBytes + 1 - data.count
                let chunkSize = min(64 * 1024, remaining)
                guard chunkSize > 0 else { break }
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                data.append(chunk)
            }
        } catch {
            return nil
        }

        guard data.count <= maximumSnapshotBytes else { return nil }
        return data
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
