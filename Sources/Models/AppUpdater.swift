// ABOUTME: Checks the local repository for updates against origin/main.
// ABOUTME: Provides a function to launch Terminal and pull/rebuild the app.

import Combine
import Foundation
import OSLog
import AppKit

private let logger = Logger(subsystem: "dockyard", category: "appUpdater")

@MainActor
final class AppUpdater: ObservableObject {
    @Published var commitsAhead: Int = 0
    @Published var isChecking: Bool = false

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
            let countProcess = Process()
            countProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            countProcess.arguments = ["rev-list", "--count", "HEAD..origin/main"]
            countProcess.currentDirectoryURL = URL(fileURLWithPath: path)

            let pipe = Pipe()
            countProcess.standardOutput = pipe

            do {
                try countProcess.run()
                countProcess.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let count = Int(output) {
                    await MainActor.run {
                        self.commitsAhead = count
                        self.isChecking = false
                    }
                } else {
                    await MainActor.run {
                        self.isChecking = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isChecking = false
                }
            }
        }
    }

    func applyUpdate() {
        let path = AppCommit.sourcePath
        let isDebug = AppCommit.configuration == "Debug"

        // Debug builds run from derived data, so `br` kills and relaunches. Release (what the
        // user runs) uses install-bg so we don't interrupt them.
        let buildMode = isDebug ? "br" : "install-bg"

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
                logger.error("Failed to execute AppleScript for update: \(errorInfo.description)")
            }
        }
    }
}
