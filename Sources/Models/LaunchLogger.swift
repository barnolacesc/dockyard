// ABOUTME: Per-workstream debug log files for agent, run, and setup launches.
// ABOUTME: Writes JSON Lines entries to ~/Library/Caches/dockyard/logs/<workstream-id>.log when detailedLogging is enabled.

import Darwin
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
    static let maximumLogFileSize = 1_048_576

    private static let privateDirectoryPermissions = 0o700
    private static let privateFilePermissions = 0o600
    private static let newline: UInt8 = 0x0A
    private static let writeLock = NSLock()

    private enum LogWriteError: Error {
        case invalidFile
        case ioFailure
    }

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
        guard var line = try? encoder.encode(entry) else { return }
        line.append(newline)
        guard line.count <= maximumLogFileSize else { return }

        writeLock.lock()
        defer { writeLock.unlock() }

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
            try append(line, to: fileURL)
        } catch {}
    }

    private static func append(_ line: Data, to fileURL: URL) throws {
        let descriptor = open(
            fileURL.path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
            mode_t(privateFilePermissions)
        )
        guard descriptor >= 0 else { throw LogWriteError.invalidFile }
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size >= 0,
              fchmod(descriptor, mode_t(privateFilePermissions)) == 0
        else {
            throw LogWriteError.invalidFile
        }

        let retainedByteBudget = maximumLogFileSize - line.count
        if metadata.st_size <= off_t(retainedByteBudget) {
            guard lseek(descriptor, 0, SEEK_END) >= 0 else { throw LogWriteError.ioFailure }
            try writeAll(line, to: descriptor)
            return
        }

        let retained = try readCompleteTail(
            from: descriptor,
            fileSize: metadata.st_size,
            maximumBytes: retainedByteBudget
        )
        let replacement = retained + line
        guard replacement.count <= maximumLogFileSize,
              ftruncate(descriptor, 0) == 0,
              lseek(descriptor, 0, SEEK_SET) >= 0
        else {
            throw LogWriteError.ioFailure
        }
        try writeAll(replacement, to: descriptor)
    }

    /// Reads at most the retention budget plus one boundary byte, then keeps
    /// only complete newest JSONL records that fit before the new entry.
    private static func readCompleteTail(
        from descriptor: Int32,
        fileSize: off_t,
        maximumBytes: Int
    ) throws -> Data {
        guard maximumBytes > 0 else { return Data() }

        let candidateStart = max(fileSize - off_t(maximumBytes), 0)
        let readStart = candidateStart > 0 ? candidateStart - 1 : 0
        let availableBytes = fileSize - readStart
        let readCount = min(maximumBytes + 1, Int(availableBytes))
        let tail = try readBytes(
            from: descriptor,
            offset: readStart,
            count: readCount
        )

        var candidate: Data
        if candidateStart > 0 {
            guard let precedingByte = tail.first else { return Data() }
            candidate = Data(tail.dropFirst())
            if precedingByte != newline {
                guard let firstNewline = candidate.firstIndex(of: newline) else { return Data() }
                candidate = Data(candidate[candidate.index(after: firstNewline)...])
            }
        } else {
            candidate = tail
        }

        guard let lastNewline = candidate.lastIndex(of: newline) else { return Data() }
        candidate = Data(candidate[...lastNewline])
        guard candidate.count <= maximumBytes else { throw LogWriteError.ioFailure }
        return candidate
    }

    private static func readBytes(
        from descriptor: Int32,
        offset: off_t,
        count: Int
    ) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        var currentOffset = offset

        while data.count < count {
            let chunkSize = min(64 * 1024, count - data.count)
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                pread(descriptor, bytes.baseAddress, chunkSize, currentOffset)
            }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw LogWriteError.ioFailure
            }
            guard bytesRead > 0 else { break }
            data.append(contentsOf: buffer.prefix(bytesRead))
            currentOffset += off_t(bytesRead)
        }
        return data
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    bytes.count - written
                )
                if result < 0 {
                    if errno == EINTR { continue }
                    throw LogWriteError.ioFailure
                }
                guard result > 0 else { throw LogWriteError.ioFailure }
                written += result
            }
        }
    }

    /// Delete the log file for a workstream. Called during archive cleanup.
    static func removeLog(for workstreamID: UUID) {
        let fileURL = logFileURL(for: workstreamID)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
