// ABOUTME: Fetches Codex usage limits via the `codex app-server` JSON-RPC `account/rateLimits/read`.
// ABOUTME: Replaces fragile TUI scraping; maps primary/secondary windows to 5-hour and weekly rows.

import Foundation

protocol CodexUsageProbeProcess: AnyObject, Sendable {
    func writeToStandardInput(_ data: Data)
    func closeStandardInput()
    func terminate()
}

typealias CodexUsageProbeProcessFactory = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ workingDirectoryURL: URL,
    _ outputHandler: @escaping @Sendable (Data) -> Void,
    _ errorHandler: @escaping @Sendable (Data) -> Void
) throws -> any CodexUsageProbeProcess

private final class FoundationCodexUsageProbeProcess: CodexUsageProbeProcess, @unchecked Sendable {
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()

    init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        outputHandler: @escaping @Sendable (Data) -> Void,
        errorHandler: @escaping @Sendable (Data) -> Void
    ) throws {
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = Self.reader(outputHandler)
        errorPipe.fileHandleForReading.readabilityHandler = Self.reader(errorHandler)

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    func writeToStandardInput(_ data: Data) {
        inputPipe.fileHandleForWriting.write(data)
    }

    func closeStandardInput() {
        try? inputPipe.fileHandleForWriting.close()
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    private static func reader(
        _ handler: @escaping @Sendable (Data) -> Void
    ) -> @Sendable (FileHandle) -> Void {
        { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            handler(chunk)
        }
    }
}

struct CodexUsageReport: Equatable {
    struct Window: Equatable {
        var usedPercent: Int
        var resetsAt: Date?
        var windowMinutes: Int?
    }

    var planType: String?
    /// Primary (short) window — Codex's 5-hour limit.
    var fiveHour: Window?
    /// Secondary (long) window — Codex's weekly limit.
    var week: Window?

    var isEmpty: Bool {
        fiveHour == nil && week == nil
    }
}

enum CodexUsageProbe {
    static let probeTimeout: TimeInterval = 8
    static let maximumResponseLineBytes = 64 * 1024

    /// Spawn `codex app-server`, perform the JSON-RPC handshake, and read the account rate limits.
    /// This is the same data Codex's `/status` shows, but fetched over the stable app-server
    /// protocol instead of scraping the interactive TUI.
    static func fetch(
        shell: String = CommandBuilder.userShell,
        timeout: TimeInterval = probeTimeout,
        maximumResponseLineBytes: Int = CodexUsageProbe.maximumResponseLineBytes,
        processFactory: CodexUsageProbeProcessFactory = {
            executableURL,
            arguments,
            workingDirectoryURL,
            outputHandler,
            errorHandler in
            try FoundationCodexUsageProbeProcess(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: workingDirectoryURL,
                outputHandler: outputHandler,
                errorHandler: errorHandler
            )
        }
    ) -> CodexUsageReport? {
        let collector = CodexUsageResponseCollector(
            maximumLineBytes: maximumResponseLineBytes
        )
        let semaphore = DispatchSemaphore(value: 0)
        let process: any CodexUsageProbeProcess
        do {
            process = try processFactory(
                URL(fileURLWithPath: shell),
                ["-lic", "codex app-server"],
                FileManager.default.homeDirectoryForCurrentUser,
                { chunk in
                    if collector.ingest(chunk) {
                        semaphore.signal()
                    }
                },
                { _ in
                    // Drain stderr continuously without retaining repository- or account-owned data.
                }
            )
        } catch {
            return nil
        }

        // `initialize` handshake then the rate-limits read, sent back-to-back. The app-server
        // processes newline-delimited requests in order, so no need to wait for the init reply.
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"dockyard","version":"1.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#,
        ].joined(separator: "\n") + "\n"
        process.writeToStandardInput(Data(requests.utf8))

        let outcome = semaphore.wait(timeout: .now() + max(0, timeout))

        process.closeStandardInput() // EOF tells the app-server to exit
        process.terminate()

        return outcome == .success ? collector.report : nil
    }

    /// Parse a single JSON-RPC response line into a usage report. Returns nil for any line that is
    /// not a rate-limits response (the init reply, notifications, shell banners, non-JSON noise).
    static func parseRateLimits(_ data: Data) -> CodexUsageReport? {
        guard let envelope = try? JSONDecoder().decode(RPCEnvelope.self, from: data),
              let limits = envelope.result?.rateLimits
        else {
            return nil
        }
        let report = CodexUsageReport(
            planType: limits.planType,
            fiveHour: limits.primary.map(window(from:)),
            week: limits.secondary.map(window(from:))
        )
        return report.isEmpty ? nil : report
    }

    private static func window(from raw: RPCWindow) -> CodexUsageReport.Window {
        CodexUsageReport.Window(
            usedPercent: max(0, min(100, raw.usedPercent)),
            resetsAt: raw.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            windowMinutes: raw.windowDurationMins.map(Int.init)
        )
    }

    // MARK: - JSON-RPC payload

    private struct RPCEnvelope: Decodable {
        let result: Result?

        struct Result: Decodable {
            let rateLimits: RateLimits?
        }

        struct RateLimits: Decodable {
            let primary: RPCWindow?
            let secondary: RPCWindow?
            let planType: String?
        }
    }

    private struct RPCWindow: Decodable {
        let usedPercent: Int
        let resetsAt: Int64?
        let windowDurationMins: Int64?
    }

}

/// Buffers one bounded stdout line and resolves the first rate-limits response. Oversized lines
/// are discarded through their newline so malformed app-server output cannot grow memory or hide
/// a later valid response. The lock protects callbacks delivered from `FileHandle` background queues.
final class CodexUsageResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumLineBytes: Int
    private var buffer = Data()
    private var discardingOversizedLine = false
    private var found: CodexUsageReport?

    init(maximumLineBytes: Int) {
        self.maximumLineBytes = max(0, maximumLineBytes)
    }

    var report: CodexUsageReport? {
        lock.lock()
        defer { lock.unlock() }
        return found
    }

    var bufferedByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    var isDiscardingOversizedLine: Bool {
        lock.lock()
        defer { lock.unlock() }
        return discardingOversizedLine
    }

    /// Returns true exactly once, when the first valid rate-limits response is found.
    func ingest(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard found == nil else { return false }

        for byte in chunk {
            if discardingOversizedLine {
                if byte == 0x0A {
                    discardingOversizedLine = false
                }
                continue
            }

            if byte == 0x0A {
                let line = buffer
                buffer.removeAll(keepingCapacity: true)
                if let report = CodexUsageProbe.parseRateLimits(line) {
                    found = report
                    return true
                }
            } else if buffer.count < maximumLineBytes {
                buffer.append(byte)
            } else {
                buffer.removeAll(keepingCapacity: false)
                discardingOversizedLine = true
            }
        }
        return false
    }
}
