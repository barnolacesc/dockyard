// ABOUTME: Runs direct git/gh subprocesses for quick actions.
// ABOUTME: Agent-delegated quick actions are routed through the live terminal surface.

import Foundation
import os

private let logger = Logger(subsystem: "dockyard", category: "quick-action")

enum QuickAction: String, CaseIterable, Identifiable {
    case commit
    case push
    case createPR
    case closePR

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .commit: return NSLocalizedString("Commit", comment: "")
        case .push: return NSLocalizedString("Push", comment: "")
        case .createPR: return NSLocalizedString("Create PR", comment: "")
        case .closePR: return NSLocalizedString("Close PR", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .commit: return "checkmark.circle"
        case .push: return "arrow.up"
        case .createPR: return "arrow.triangle.pull"
        case .closePR: return "xmark.circle"
        }
    }

    /// Whether this action should be sent to the live Coding Agent.
    var delegatesToAgent: Bool {
        switch self {
        case .commit, .createPR: return true
        case .push, .closePR: return false
        }
    }

    var requiresGitHubRemote: Bool {
        switch self {
        case .createPR, .closePR: return true
        case .commit, .push: return false
        }
    }

    var prompt: String? {
        switch self {
        case .commit:
            return "Stage and commit all changes in the working tree with a good commit message based on the changes. Do not push."
        case .createPR:
            return "Create a pull request for the current changes. Write a clear title and description based on what we've been working on."
        case .push, .closePR:
            return nil
        }
    }

    func disabledReason(ghPath: String?) -> String? {
        if self == .closePR, ghPath == nil {
            return NSLocalizedString("gh CLI is not installed.", comment: "")
        }
        return nil
    }
}

enum QuickActionState: Equatable {
    case idle
    case running(QuickAction)
    case succeeded(QuickAction)
    case failed(QuickAction)
}

struct QuickActionLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let action: QuickAction
    let command: String
    var output: String
    var exitCode: Int32?
}

@MainActor
final class QuickActionRunner: ObservableObject {
    @Published var state: QuickActionState = .idle
    @Published var log: [QuickActionLogEntry] = []
    var onSuccess: ((QuickAction) -> Void)?
    private var runningProcess: Process?
    private var dismissWork: DispatchWorkItem?

    func run(
        action: QuickAction,
        ghPath: String?,
        workingDirectory: String,
        branchName: String? = nil
    ) {
        guard !action.delegatesToAgent else { return }
        guard case .idle = state else { return }

        state = .running(action)
        dismissWork?.cancel()

        switch action {
        case .commit, .createPR:
            break
        case .push:
            runPush(workingDirectory: workingDirectory)
        case .closePR:
            guard let ghPath, let branchName else {
                state = .idle
                return
            }
            runClosePR(ghPath: ghPath, branchName: branchName, workingDirectory: workingDirectory)
        }
    }

    private func runPush(workingDirectory: String) {
        let dir = workingDirectory
        let actionRaw = QuickAction.push.rawValue
        let command = "git push -u origin HEAD"

        appendLog(action: .push, command: command)
        logger.info("Quick action \(actionRaw) starting in \(dir)")

        Task.detached {
            let result = GitOperations.pushCurrentBranch(at: dir)
            await MainActor.run {
                self.updateLog(output: result.output, exitCode: result.success ? 0 : 1)
                self.runningProcess = nil
                self.state = result.success ? .succeeded(.push) : .failed(.push)
                if result.success {
                    self.onSuccess?(.push)
                }
                self.scheduleDismiss()
            }
        }
    }

    private func runClosePR(ghPath: String, branchName: String, workingDirectory: String) {
        let command = "\(ghPath) pr close \(branchName) --comment 'Closed from Dockyard'"

        appendLog(action: .closePR, command: command)
        logger.info("Quick action closePR starting in \(workingDirectory)")

        let dir = workingDirectory
        let path = ghPath
        let branch = branchName
        Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["pr", "close", branch, "--comment", "Closed from Dockyard"]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = pipe
            process.standardError = pipe
            let success: Bool
            let output: String
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output = String(data: data, encoding: .utf8) ?? ""
                success = process.terminationStatus == 0
            } catch {
                output = "Failed to launch: \(error.localizedDescription)"
                success = false
            }
            await MainActor.run {
                self.updateLog(output: output, exitCode: success ? 0 : 1)
                self.runningProcess = nil
                self.state = success ? .succeeded(.closePR) : .failed(.closePR)
                if success {
                    self.onSuccess?(.closePR)
                }
                self.scheduleDismiss()
            }
        }
    }

    @discardableResult
    private func appendLog(action: QuickAction, command: String) -> UUID {
        let entry = QuickActionLogEntry(
            timestamp: Date(),
            action: action,
            command: command,
            output: ""
        )
        log.append(entry)
        return entry.id
    }

    private func updateLog(output: String, exitCode: Int32) {
        guard let idx = log.indices.last else { return }
        log[idx].output = output
        log[idx].exitCode = exitCode
    }

    func cancel() {
        runningProcess?.terminate()
        runningProcess = nil
        state = .idle
    }

    func clearLog() {
        log.removeAll()
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.state = .idle
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
