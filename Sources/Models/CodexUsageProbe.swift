// ABOUTME: Fetches Codex usage limits via the `codex app-server` JSON-RPC `account/rateLimits/read`.
// ABOUTME: Replaces fragile TUI scraping; maps primary/secondary windows to 5-hour and weekly rows.

import Foundation

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
    private static let probeTimeout: TimeInterval = 8

    /// Spawn `codex app-server`, perform the JSON-RPC handshake, and read the account rate limits.
    /// This is the same data Codex's `/status` shows, but fetched over the stable app-server
    /// protocol instead of scraping the interactive TUI.
    static func fetch(shell: String = CommandBuilder.userShell) -> CodexUsageReport? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", "codex app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let outHandle = outPipe.fileHandleForReading
        let collector = ResponseCollector()
        let semaphore = DispatchSemaphore(value: 0)

        // The readability handler is invoked serially, so its access to the collector is safe.
        outHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            if collector.ingest(chunk) {
                semaphore.signal()
            }
        }

        // `initialize` handshake then the rate-limits read, sent back-to-back. The app-server
        // processes newline-delimited requests in order, so no need to wait for the init reply.
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"dockyard","version":"1.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#,
        ].joined(separator: "\n") + "\n"
        inPipe.fileHandleForWriting.write(Data(requests.utf8))

        let outcome = semaphore.wait(timeout: .now() + probeTimeout)

        outHandle.readabilityHandler = nil
        try? inPipe.fileHandleForWriting.close() // EOF tells the app-server to exit
        if process.isRunning { process.terminate() }

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

    /// Buffers stdout and resolves the first line that parses as a rate-limits response. Guarded by
    /// a lock because `FileHandle.readabilityHandler` runs on a background queue.
    private final class ResponseCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var found: CodexUsageReport?

        var report: CodexUsageReport? {
            lock.lock()
            defer { lock.unlock() }
            return found
        }

        /// Returns true once a rate-limits response has been found.
        func ingest(_ chunk: Data) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                if let report = CodexUsageProbe.parseRateLimits(line) {
                    found = report
                    return true
                }
            }
            return false
        }
    }
}
