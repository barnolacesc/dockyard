// ABOUTME: Fetches real Antigravity CLI quota/usage by running `agy -p '/usage' --output-format json`.
// ABOUTME: Parses 5-hour and weekly usage windows with reset times for the sidebar usage meter.

import Foundation

protocol AgyUsageProbeProcess: AnyObject, Sendable {
    func terminate()
}

typealias AgyUsageProbeProcessFactory = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ workingDirectoryURL: URL,
    _ outputHandler: @escaping @Sendable (Data) -> Void,
    _ completion: @escaping @Sendable (Int32) -> Void
) throws -> any AgyUsageProbeProcess

private final class FoundationAgyUsageProbeProcess: AgyUsageProbeProcess, @unchecked Sendable {
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

final class AgyUsageProbeOperation: @unchecked Sendable {
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

struct AgyUsageReport: Equatable {
    struct Window: Equatable {
        var usedPercent: Int
        var remainingPercent: Int
        var resetsAt: Date?
    }

    var fiveHour: Window?
    var week: Window?

    var isEmpty: Bool {
        fiveHour == nil && week == nil
    }
}

enum AgyUsageProbe {
    static let probeTimeout: TimeInterval = 8
    static let maximumOutputBytes = 64 * 1024

    /// Run `agy -p '/usage' --output-format json` via login shell and parse the result.
    /// Returns nil if agy isn't installed, call fails, or output cannot be parsed.
    /// Must be called off the main thread.
    static func fetch(
        shell: String = CommandBuilder.userShell,
        timeout: TimeInterval = probeTimeout,
        maximumOutputBytes: Int = AgyUsageProbe.maximumOutputBytes,
        processFactory: AgyUsageProbeProcessFactory = { executableURL, arguments, workingDirectoryURL, outputHandler, completion in
            try FoundationAgyUsageProbeProcess(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectoryURL: workingDirectoryURL,
                outputHandler: outputHandler,
                completion: completion
            )
        }
    ) -> AgyUsageReport? {
        let operation = AgyUsageProbeOperation(maximumOutputBytes: maximumOutputBytes)
        let completed = DispatchSemaphore(value: 0)
        let process: any AgyUsageProbeProcess
        do {
            process = try processFactory(
                URL(fileURLWithPath: shell),
                ["-lic", "agy -p '/usage' --output-format json"],
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

    /// Parses JSON envelope, falls back to text parsing if needed.
    static func parse(_ data: Data) -> AgyUsageReport? {
        if let jsonReport = parseJSON(data) {
            return jsonReport
        }
        if let text = String(data: data, encoding: .utf8) {
            return parseText(text)
        }
        return nil
    }

    private struct Envelope: Decodable {
        let command: CommandWrapper?
        let response: String?

        struct CommandWrapper: Decodable {
            let name: String?
            let data: DataPayload?
        }

        struct DataPayload: Decodable {
            let groups: [Group]?
        }

        struct Group: Decodable {
            let name: String?
            let buckets: [Bucket]?
        }

        struct Bucket: Decodable {
            let id: String?
            let name: String?
            let window: String?
            let remaining_fraction: Double?
            let reset_time: String?
        }
    }

    private static func parseJSON(_ data: Data) -> AgyUsageReport? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
        }

        let groups = envelope.command?.data?.groups ?? []
        // Choose group with lowest remaining fraction (active usage) or the first non-empty group
        let selectedGroup = groups.min(by: { g1, g2 in
            let min1 = g1.buckets?.compactMap(\.remaining_fraction).min() ?? 1.0
            let min2 = g2.buckets?.compactMap(\.remaining_fraction).min() ?? 1.0
            return min1 < min2
        }) ?? groups.first

        var report = AgyUsageReport()
        let dateFormatter = ISO8601DateFormatter()

        for bucket in selectedGroup?.buckets ?? [] {
            let fraction = bucket.remaining_fraction ?? 1.0
            let remainingPercent = max(0, min(100, Int(round(fraction * 100))))
            let usedPercent = max(0, min(100, 100 - remainingPercent))
            let resetsAt = bucket.reset_time.flatMap { dateFormatter.date(from: $0) }
            let window = AgyUsageReport.Window(
                usedPercent: usedPercent,
                remainingPercent: remainingPercent,
                resetsAt: resetsAt
            )

            let isFiveHour = bucket.window == "5h" || (bucket.id?.contains("5h") ?? false)
            let isWeekly = bucket.window == "weekly" || (bucket.id?.contains("weekly") ?? false)

            if isFiveHour {
                report.fiveHour = window
            } else if isWeekly {
                report.week = window
            }
        }

        if !report.isEmpty {
            return report
        }

        // Try parsing the text response inside the JSON envelope if buckets were missing
        if let response = envelope.response {
            return parseText(response)
        }

        return nil
    }

    /// Parse plain text output, e.g.:
    /// `Gemini Models          Weekly Limit Remaining     96%   2026-09-25T19:17:02Z`
    /// `Gemini Models          Five Hour Limit Remaining  82%   2026-09-19T00:17:02Z`
    static func parseText(_ text: String) -> AgyUsageReport? {
        var report = AgyUsageReport()
        let dateFormatter = ISO8601DateFormatter()

        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine)
            let lower = line.lowercased()

            guard let remainingPercent = extractPercent(in: line) else { continue }
            let usedPercent = max(0, min(100, 100 - remainingPercent))
            let resetsAt = extractDate(in: line, formatter: dateFormatter)
            let window = AgyUsageReport.Window(
                usedPercent: usedPercent,
                remainingPercent: remainingPercent,
                resetsAt: resetsAt
            )

            if lower.contains("five hour") || lower.contains("5-hour") || lower.contains("5h") {
                report.fiveHour = window
            } else if lower.contains("weekly") || lower.contains("7-day") || lower.contains("7d") {
                report.week = window
            }
        }

        return report.isEmpty ? nil : report
    }

    private static func extractPercent(in line: String) -> Int? {
        guard let range = line.range(of: #"\b\d{1,3}%"#, options: .regularExpression) else { return nil }
        return Int(line[range].dropLast())
    }

    private static func extractDate(in line: String, formatter: ISO8601DateFormatter) -> Date? {
        guard let range = line.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"#, options: .regularExpression) else { return nil }
        return formatter.date(from: String(line[range]))
    }
}
