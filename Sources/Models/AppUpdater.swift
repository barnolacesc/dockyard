// ABOUTME: Checks the running app's embedded commit for updates against origin/main.
// ABOUTME: Installs source updates in the background, then offers a controlled relaunch.

import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "dockyard", category: "appUpdater")

struct UpdateCheckProcessResult {
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
        from appCommit: String,
        processFactory: UpdateCheckProcessFactory = defaultUpdateCheckProcessFactory
    ) -> Int? {
        let executableURL = URL(fileURLWithPath: "/usr/bin/git")
        let revision = appCommit.range(of: "^[0-9a-fA-F]{7,40}$", options: .regularExpression) == nil
            ? "HEAD"
            : appCommit
        let arguments = ["rev-list", "--count", "\(revision)..origin/main"]
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

    static func latestNewReleaseTag(
        at path: String,
        from appCommit: String,
        processFactory: UpdateCheckProcessFactory = defaultUpdateCheckProcessFactory
    ) -> String? {
        let executableURL = URL(fileURLWithPath: "/usr/bin/git")
        let revision = appCommit.range(of: "^[0-9a-fA-F]{7,40}$", options: .regularExpression) == nil
            ? "HEAD"
            : appCommit
        let arguments = ["tag", "--merged", "origin/main", "--no-merged", revision, "--sort=-v:refname"]
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
              let output = String(data: result.output, encoding: .utf8)
        else {
            return nil
        }
        let releaseTagRegex = try? NSRegularExpression(pattern: "^v[0-9]+\\.[0-9]+\\.[0-9]+$")
        let tags = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { tag in
                guard !tag.isEmpty else { return false }
                guard let regex = releaseTagRegex else { return tag.hasPrefix("v") }
                return regex.firstMatch(in: tag, range: NSRange(location: 0, length: tag.utf16.count)) != nil
            }
        return tags.first
    }
}

enum UpdateChannel: String, CaseIterable, Identifiable {
    case releases
    case mainCommits = "main"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .releases:
            return NSLocalizedString("Official releases", comment: "Update channel: official releases only")
        case .mainCommits:
            return NSLocalizedString("Every commit to main", comment: "Update channel: continuous updates on main")
        }
    }

    var description: String {
        switch self {
        case .releases:
            return NSLocalizedString("Only notify when a new official release tag is published.", comment: "Update channel description: official releases")
        case .mainCommits:
            return NSLocalizedString("Notify whenever new changes are pushed to main.", comment: "Update channel description: main commits")
        }
    }
}

enum SourceUpdateBuildMode {
    static func resolve(configuration: String) -> String {
        configuration == "Debug" ? "build" : "install-bg"
    }
}

@MainActor
final class AppUpdater: ObservableObject {
    nonisolated static let channelStorageKey = "dockyard.updateChannel"

    nonisolated static func loadChannel(from defaults: UserDefaults = .standard) -> UpdateChannel {
        if let raw = defaults.string(forKey: channelStorageKey),
           let channel = UpdateChannel(rawValue: raw)
        {
            return channel
        }
        if defaults.bool(forKey: "dockyard.bleedingEdge") {
            return .mainCommits
        }
        return .releases
    }

    @Published var commitsAhead: Int = 0
    @Published var availableReleaseTag: String? = nil
    @Published var isChecking: Bool = false
    @Published private(set) var isUpdating = false
    @Published private(set) var isUpdateReady = false
    /// Set once per session when an update is first detected, so the UI can surface a
    /// one-time prompt instead of silently showing a small button.
    @Published var shouldPromptUpdate: Bool = false
    @Published var shouldPromptUpdateReady: Bool = false

    var hasUpdate: Bool {
        availableReleaseTag != nil || commitsAhead > 0
    }

    var isSourceBuild: Bool {
        let path = AppCommit.sourcePath
        guard !path.isEmpty else { return false }
        let gitPath = URL(fileURLWithPath: path).appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: gitPath)
    }

    private var hasPromptedThisSession = false
    private var updateTask: Task<Void, Never>?
    private var activeCheckTask: Task<Void, Never>?
    private var currentCheckID = UUID()
    private var hasPendingChannelCheck = false

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
        activeCheckTask?.cancel()
    }

    func setChannel(_ channel: UpdateChannel) {
        UserDefaults.standard.set(channel.rawValue, forKey: Self.channelStorageKey)
        UserDefaults.standard.set(channel == .mainCommits, forKey: "dockyard.bleedingEdge")
        hasPromptedThisSession = false
        if isChecking {
            hasPendingChannelCheck = true
            activeCheckTask?.cancel()
        } else {
            checkForUpdates()
        }
    }

    func checkForUpdates() {
        guard !isUpdating, !isUpdateReady else { return }
        if isChecking {
            return
        }
        isChecking = true
        let checkID = UUID()
        currentCheckID = checkID

        let channel = Self.loadChannel()
        let path = AppCommit.sourcePath
        let commitHash = AppCommit.hash

        activeCheckTask = Task { @MainActor [weak self] in
            let (count, tag) = await Task.detached { () -> (Int?, String?) in
                // 1. Fetch from origin main with tags
                let fetchProcess = Process()
                fetchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                fetchProcess.arguments = ["fetch", "origin", "main", "--tags"]
                fetchProcess.currentDirectoryURL = URL(fileURLWithPath: path)
                try? fetchProcess.run()
                fetchProcess.waitUntilExit()

                guard !Task.isCancelled else { return (nil, nil) }

                // 2. Query git based on selected channel
                let count: Int?
                let tag: String?
                switch channel {
                case .releases:
                    tag = UpdateCheckCommandRunner.latestNewReleaseTag(at: path, from: commitHash)
                    count = 0
                case .mainCommits:
                    tag = nil
                    count = UpdateCheckCommandRunner.commitsAhead(at: path, from: commitHash)
                }
                return (count, tag)
            }.value

            guard let self else { return }
            self.isChecking = false
            self.activeCheckTask = nil

            if self.hasPendingChannelCheck {
                self.hasPendingChannelCheck = false
                self.checkForUpdates()
                return
            }

            guard !Task.isCancelled, self.currentCheckID == checkID else { return }
            self.commitsAhead = count ?? 0
            self.availableReleaseTag = tag

            let hasNewUpdate = (tag != nil) || ((count ?? 0) > 0)
            if !hasNewUpdate {
                self.shouldPromptUpdate = false
            } else if !self.hasPromptedThisSession {
                self.hasPromptedThisSession = true
                self.shouldPromptUpdate = true
            }
        }
    }

    func applyUpdate() {
        guard !isUpdating, !isUpdateReady else { return }
        isUpdating = true
        shouldPromptUpdate = false
        let path = AppCommit.sourcePath
        // Keep the running process alive until the replacement bundle is completely ready.
        // Killing and reopening from inside the worker races Launch Services and prevents the
        // app from reporting success. The user initiates a controlled restart after install.
        let buildMode = SourceUpdateBuildMode.resolve(configuration: AppCommit.configuration)
        let targetRef = availableReleaseTag ?? ""

        // Delegate the git reconciliation + build to a hardened, idempotent script so the
        // update survives divergent branches and dirty build artifacts. Fall back to the
        // inline pull only if the script is missing (older checkouts).
        let logURL = AppConstants.cacheDirectory.appendingPathComponent("self-update.log")
        Task {
            let succeeded = await Task.detached(priority: .utility) {
                do {
                    try FileManager.default.createDirectory(
                        at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    FileManager.default.createFile(atPath: logURL.path, contents: nil)
                    let log = try FileHandle(forWritingTo: logURL)
                    defer { try? log.close() }
                    let process = Process()
                    // Ignore hangups so the rebuild can replace and relaunch its parent app.
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
                    process.arguments = ["/bin/sh", "-c", """
                    if [ -x ./scripts/self-update.sh ]; then
                        exec ./scripts/self-update.sh "$1" "$2"
                    else
                        if [ -n "$2" ]; then
                            git fetch origin --tags && git checkout "$2" && ./scripts/dev.sh "$1"
                        else
                            git fetch origin main && git merge --ff-only origin/main && ./scripts/dev.sh "$1"
                        fi
                    fi
                    """, "dockyard-update", buildMode, targetRef]
                    process.currentDirectoryURL = URL(fileURLWithPath: path)
                    var environment = ProcessInfo.processInfo.environment
                    let shell = CommandBuilder.resolvedUserShell(environment: environment)
                    if let shellPath = CommandLineTools.loginShellPath(shell: shell) {
                        environment["PATH"] = shellPath
                    }
                    environment["GIT_TERMINAL_PROMPT"] = "0"
                    process.environment = environment
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = log
                    process.standardError = log
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus == 0
                } catch {
                    logger.error("Failed to launch update: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }.value
            isUpdating = false
            if succeeded {
                commitsAhead = 0
                availableReleaseTag = nil
                isUpdateReady = true
                shouldPromptUpdateReady = true
                UserDefaults.standard.set(
                    AppCommit.hash,
                    forKey: WhatsNewGate.pendingSourceUpdateCommitKey
                )
            } else {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Update failed", comment: "Source update failure title")
                alert.informativeText = String(
                    format: NSLocalizedString("The update could not be completed. See the log at %@ for details.", comment: "Source update failure log location"),
                    logURL.path
                )
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.runModal()
            }
        }
    }

    func restartToApplyUpdate() {
        guard isUpdateReady else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = [
            "/bin/sh", "-c", """
            while kill -0 "$1" 2>/dev/null; do sleep 0.1; done
            exec /usr/bin/open -n "$2"
            """,
            "dockyard-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            logger.error("Failed to relaunch after update: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Restart failed", comment: "Source update restart failure title")
            alert.informativeText = NSLocalizedString(
                "Dockyard was updated, but it could not restart automatically. Quit and reopen it to apply the update.",
                comment: "Source update restart failure instructions"
            )
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.runModal()
        }
    }
}
