// ABOUTME: Fetches REAL Claude usage by running `claude -p /usage` (a client-side command —
// ABOUTME: no model call, no token/quota cost) and parsing the session/week percentages.

import Foundation

protocol ClaudeUsageProbeProcess: AnyObject, Sendable {
    func terminate()
}

typealias ClaudeUsageProbeProcessFactory = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ workingDirectoryURL: URL,
    _ outputHandler: @escaping @Sendable (Data) -> Void,
    _ completion: @escaping @Sendable (Int32) -> Void
) throws -> any ClaudeUsageProbeProcess

private final class FoundationClaudeUsageProbeProcess: ClaudeUsageProbeProcess, @unchecked Sendable {
    private let process: Process
    private let outputPipe: Pipe
    private let readerFinished = DispatchSemaphore(value: 0)
    private let outputHandler: @Sendable (Data) -> Void

    init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        outputHandler: @escaping @Sendable (Data) -> Void,
        completion: @escaping @Sendable (Int32) -> Void
    ) throws {
        let process = Process()
        let outputPipe = Pipe()
        self.process = process
        self.outputPipe = outputPipe
        self.outputHandler = outputHandler

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            self.readerFinished.wait()
            completion(terminatedProcess.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw error
        }

        startOutputReader()
    }

    private func startOutputReader() {
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { readerFinished.signal() }
            let handle = outputPipe.fileHandleForReading
            while let chunk = try? handle.read(upToCount: 16 * 1024), !chunk.isEmpty {
                outputHandler(chunk)
            }
        }
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

final class ClaudeUsageProbeOperation: @unchecked Sendable {
    enum Outcome: Equatable {
        case completed(output: Data, exitCode: Int32)
        case timedOut
    }

    private let lock = NSLock()
    private let maximumOutputBytes: Int
    private var output = Data()
    private var resolvedOutcome: Outcome?

    init(maximumOutputBytes: Int) {
        self.maximumOutputBytes = max(0, maximumOutputBytes)
    }

    var outcome: Outcome? {
        lock.withLock { resolvedOutcome }
    }

    var bufferedOutputByteCount: Int {
        lock.withLock { output.count }
    }

    func ingest(_ chunk: Data) {
        lock.withLock {
            guard resolvedOutcome == nil, output.count < maximumOutputBytes else { return }
            output.append(chunk.prefix(maximumOutputBytes - output.count))
        }
    }

    @discardableResult
    func complete(exitCode: Int32) -> Bool {
        lock.withLock {
            guard resolvedOutcome == nil else { return false }
            resolvedOutcome = .completed(output: output, exitCode: exitCode)
            return true
        }
    }

    @discardableResult
    func timeOut() -> Bool {
        resolve(.timedOut)
    }

    private func resolve(_ outcome: Outcome) -> Bool {
        lock.withLock {
            guard resolvedOutcome == nil else { return false }
            resolvedOutcome = outcome
            return true
        }
    }
}

/// Real usage figures parsed from Claude Code's `/usage` output. Unlike the local-transcript
/// estimate, these are the authoritative account numbers (all models, web + CLI).
struct ClaudeUsageReport: Equatable {
    struct Window: Equatable {
        var percentUsed: Int
        var resetText: String?
    }

    var session: Window?
    var week: Window?

    var isEmpty: Bool { session == nil && week == nil }
}

enum ClaudeUsageProbe {
    static let probeTimeout: TimeInterval = 8
    static let maximumOutputBytes = 64 * 1024

    /// Run `claude -p /usage --output-format json` via the login shell and parse the result.
    /// `/usage` is intercepted client-side, so this makes no model request (cost/quota = 0).
    /// Returns nil if claude isn't installed, the call fails, or nothing parseable comes back.
    /// Must be called off the main actor (it blocks on a subprocess).
    static func fetch(
        shell: String = CommandBuilder.userShell,
        timeout: TimeInterval = probeTimeout,
        maximumOutputBytes: Int = ClaudeUsageProbe.maximumOutputBytes,
        processFactory: ClaudeUsageProbeProcessFactory = { executableURL, arguments, workingDirectoryURL, outputHandler, completion in
            try FoundationClaudeUsageProbeProcess(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: workingDirectoryURL,
                outputHandler: outputHandler,
                completion: completion
            )
        }
    ) -> ClaudeUsageReport? {
        let operation = ClaudeUsageProbeOperation(maximumOutputBytes: maximumOutputBytes)
        let completed = DispatchSemaphore(value: 0)
        let process: any ClaudeUsageProbeProcess
        do {
            process = try processFactory(
                URL(fileURLWithPath: shell),
                ["-lic", "claude -p '/usage' --output-format json"],
                FileManager.default.homeDirectoryForCurrentUser,
                { operation.ingest($0) },
                { exitCode in
                    if operation.complete(exitCode: exitCode) {
                        completed.signal()
                    }
                }
            )
        } catch {
            return nil
        }

        if completed.wait(timeout: .now() + max(0, timeout)) == .timedOut,
           operation.timeOut()
        {
            process.terminate()
        }

        guard case let .completed(output, exitCode) = operation.outcome,
              exitCode == 0
        else {
            return nil
        }
        return parse(output)
    }

    /// Parse the `--output-format json` envelope, then the human-readable `result` text.
    static func parse(_ data: Data) -> ClaudeUsageReport? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? String else { return nil }
        return parseText(result)
    }

    /// Parse the `/usage` body, e.g.:
    /// `Current session: 63% used · resets Jun 14 at 3pm (Europe/Madrid)`
    /// `Current week (all models): 43% used · resets Jun 17 at 9am (Europe/Madrid)`
    static func parseText(_ text: String) -> ClaudeUsageReport? {
        var report = ClaudeUsageReport()
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine)
            let lower = line.lowercased()
            guard lower.contains("% used"), let percent = firstPercent(in: line) else { continue }
            let window = ClaudeUsageReport.Window(percentUsed: percent, resetText: resetText(in: line))
            if lower.contains("session") {
                report.session = window
            } else if lower.contains("week") {
                report.week = window
            }
        }
        return report.isEmpty ? nil : report
    }

    /// First integer immediately followed by `%`.
    private static func firstPercent(in line: String) -> Int? {
        guard let range = line.range(of: #"\d+%"#, options: .regularExpression) else { return nil }
        return Int(line[range].dropLast())
    }

    /// Text after "resets ", trimmed and stripped of a trailing timezone parenthetical.
    private static func resetText(in line: String) -> String? {
        guard let r = line.range(of: "resets ") else { return nil }
        var rest = String(line[r.upperBound...])
        if let paren = rest.firstIndex(of: "(") {
            rest = String(rest[..<paren])
        }
        let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
