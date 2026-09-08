// ABOUTME: Checks the local repository for updates against origin/main.
// ABOUTME: Provides a function to launch Terminal and pull/rebuild the app.

import Combine
import Foundation
import OSLog
import AppKit

private let logger = Logger(subsystem: "dockyard", category: "appUpdater")

struct UpdateCheckProcessResult: Sendable {
    let output: Data
    let terminationStatus: Int32
    let outputExceededLimit: Bool
    let didFinishOutput: Bool
}

final class UpdateCheckOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumOutputBytes: Int
    private var output = Data()
    private var outputExceededLimit = false

    init(maximumOutputBytes: Int) {
        self.maximumOutputBytes = max(0, maximumOutputBytes)
    }

    /// Retains at most the configured cap while allowing all process output to be drained.
    func ingest(_ chunk: Data) {
        lock.withLock {
            let remaining = max(0, maximumOutputBytes - output.count)
            if remaining > 0 {
                output.append(contentsOf: chunk.prefix(remaining))
            }
            if chunk.count > remaining {
                outputExceededLimit = true
            }
        }
    }

    var snapshot: (output: Data, outputExceededLimit: Bool) {
        lock.withLock { (output, outputExceededLimit) }
    }
}

protocol UpdateCheckProcess: AnyObject, Sendable {
    func run() throws
    func waitForExit() -> UpdateCheckProcessResult
}

typealias UpdateCheckProcessFactory = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ workingDirectoryURL: URL,
    _ maximumOutputBytes: Int
) throws -> any UpdateCheckProcess

final class FoundationUpdateCheckProcess: UpdateCheckProcess, @unchecked Sendable {
    private let process = Process()
    private let outputPipe = Pipe()
    private let collector: UpdateCheckOutputCollector
    private let outputGroup = DispatchGroup()
    private var outputReaderStarted = false

    init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        maximumOutputBytes: Int
    ) {
        collector = UpdateCheckOutputCollector(maximumOutputBytes: maximumOutputBytes)
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = outputPipe
    }

    func run() throws {
        try process.run()
        outputReaderStarted = true
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { outputGroup.leave() }
            let handle = outputPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                collector.ingest(chunk)
            }
        }
    }

    func waitForExit() -> UpdateCheckProcessResult {
        process.waitUntilExit()
        if outputReaderStarted {
            outputGroup.wait()
        }
        let snapshot = collector.snapshot
        return UpdateCheckProcessResult(
            output: snapshot.output,
            terminationStatus: process.terminationStatus,
            outputExceededLimit: snapshot.outputExceededLimit,
            didFinishOutput: outputReaderStarted
        )
    }
}

let defaultUpdateCheckProcessFactory: UpdateCheckProcessFactory = {
    executableURL,
    arguments,
    workingDirectoryURL,
    maximumOutputBytes in
    FoundationUpdateCheckProcess(
        executableURL: executableURL,
        arguments: arguments,
        workingDirectoryURL: workingDirectoryURL,
        maximumOutputBytes: maximumOutputBytes
    )
}

enum UpdateCheckCommandRunner {
    static let maximumOutputBytes = 64 * 1024

    static func commitsAhead(
        at path: String,
        processFactory: UpdateCheckProcessFactory = defaultUpdateCheckProcessFactory
    ) -> Int? {
        let executableURL = URL(fileURLWithPath: "/usr/bin/git")
        let arguments = ["rev-list", "--count", "HEAD..origin/main"]
        let workingDirectoryURL = URL(fileURLWithPath: path)

        let process: any UpdateCheckProcess
        do {
            process = try processFactory(
                executableURL,
                arguments,
                workingDirectoryURL,
                maximumOutputBytes
            )
            try process.run()
        } catch {
            return nil
        }

        let result = process.waitForExit()
        guard result.terminationStatus == 0,
              result.didFinishOutput,
              !result.outputExceededLimit,
              let output = String(data: result.output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let count = Int(output),
              count >= 0
        else {
            return nil
        }
        return count
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    @Published var commitsAhead: Int = 0
    @Published var isChecking: Bool = false
    /// Set once per session when an update is first detected, so the UI can surface a
    /// one-time prompt instead of silently showing a small button.
    @Published var shouldPromptUpdate: Bool = false

    private var hasPromptedThisSession = false
    private var updateTask: Task<Void, Never>?

    init() {
        // Initial check
        checkForUpdates()

        // Periodic check every 15 minutes
        updateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900 * 1_000_000_000)
                if Task.isCancelled { break }
                self?.checkForUpdates()
            }
        }
    }

    deinit {
        updateTask?.cancel()
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        Task.detached {
            let path = AppCommit.sourcePath
            
            // 1. Fetch from origin main
            let fetchProcess = Process()
            fetchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            fetchProcess.arguments = ["fetch", "origin", "main"]
            fetchProcess.currentDirectoryURL = URL(fileURLWithPath: path)
            try? fetchProcess.run()
            fetchProcess.waitUntilExit()

            // 2. Count commits
            let count = UpdateCheckCommandRunner.commitsAhead(at: path)
            await MainActor.run {
                self.isChecking = false
                if let count {
                    self.commitsAhead = count
                    if count > 0 && !self.hasPromptedThisSession {
                        self.hasPromptedThisSession = true
                        self.shouldPromptUpdate = true
                    }
                }
            }
        }
    }

    func applyUpdate() {
        let path = AppCommit.sourcePath
        let isDebug = AppCommit.configuration == "Debug"

        // Debug builds run from derived data, so `br` kills and relaunches. Release (what the
        // user runs) uses `install`, which rebuilds then swaps the bundle in /Applications and
        // relaunches it automatically — no manual restart needed.
        let buildMode = isDebug ? "br" : "install"

        // Delegate the git reconciliation + build to a hardened, idempotent script so the
        // update survives divergent branches and dirty build artifacts. Fall back to the
        // inline pull only if the script is missing (older checkouts).
        let scriptPath = "\(path)/scripts/self-update.sh"
        let command: String
        if FileManager.default.isExecutableFile(atPath: scriptPath) {
            command = "cd '\(path)' && ./scripts/self-update.sh \(buildMode)"
        } else {
            command = "cd '\(path)' && git fetch origin main && git merge --ff-only origin/main && ./scripts/dev.sh \(buildMode)"
        }

        // Create an AppleScript to open Terminal and run the command.
        let scriptSource = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """

        if let appleScript = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
            if let errorInfo = errorInfo {
                logger.error("Failed to execute AppleScript for update: \(errorInfo.description, privacy: .public)")
            }
        }
    }
}
