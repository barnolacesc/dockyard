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

struct QuickActionProcessResult: Sendable {
    let output: String
    let exitCode: Int32
}

protocol QuickActionProcess: AnyObject, Sendable {
    func terminate()
}

typealias QuickActionProcessFactory = @MainActor (
    _ executableURL: URL,
    _ arguments: [String],
    _ workingDirectoryURL: URL,
    _ completion: @escaping @Sendable (QuickActionProcessResult) -> Void
) throws -> any QuickActionProcess

private final class FoundationQuickActionProcess: QuickActionProcess, @unchecked Sendable {
    private let process: Process
    private let pipe: Pipe
    private let completion: @Sendable (QuickActionProcessResult) -> Void

    init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        completion: @escaping @Sendable (QuickActionProcessResult) -> Void
    ) throws {
        let process = Process()
        let pipe = Pipe()
        self.process = process
        self.pipe = pipe
        self.completion = completion

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] terminatedProcess in
            guard let self else { return }
            let data = self.pipe.fileHandleForReading.readDataToEndOfFile()
            self.completion(
                QuickActionProcessResult(
                    output: String(data: data, encoding: .utf8) ?? "",
                    exitCode: terminatedProcess.terminationStatus
                )
            )
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw error
        }
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

@MainActor
final class QuickActionRunner: ObservableObject {
    @Published var state: QuickActionState = .idle
    @Published var log: [QuickActionLogEntry] = []
    var onSuccess: ((QuickAction) -> Void)?
    private let processFactory: QuickActionProcessFactory
    private var runningProcess: (any QuickActionProcess)?
    private var activeOperationID: UUID?
    private var dismissWork: DispatchWorkItem?

    init(processFactory: @escaping QuickActionProcessFactory = { executableURL, arguments, workingDirectoryURL, completion in
        try FoundationQuickActionProcess(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            completion: completion
        )
    }) {
        self.processFactory = processFactory
    }

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
        logger.info("Quick action \(actionRaw, privacy: .public) starting in \(dir, privacy: .public)")

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
        logger.info("Quick action closePR starting in \(workingDirectory, privacy: .public)")

        let operationID = UUID()
        activeOperationID = operationID

        do {
            runningProcess = try processFactory(
                URL(fileURLWithPath: ghPath),
                ["pr", "close", branchName, "--comment", "Closed from Dockyard"],
                URL(fileURLWithPath: workingDirectory)
            ) { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.finishClosePR(operationID: operationID, result: result)
                }
            }
        } catch {
            activeOperationID = nil
            runningProcess = nil
            updateLog(output: "Failed to launch: \(error.localizedDescription)", exitCode: 1)
            state = .failed(.closePR)
            scheduleDismiss()
        }
    }

    private func finishClosePR(operationID: UUID, result: QuickActionProcessResult) {
        guard activeOperationID == operationID else { return }

        activeOperationID = nil
        runningProcess = nil
        updateLog(output: result.output, exitCode: result.exitCode)

        let succeeded = result.exitCode == 0
        state = succeeded ? .succeeded(.closePR) : .failed(.closePR)
        if succeeded {
            onSuccess?(.closePR)
        }
        scheduleDismiss()
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
        dismissWork?.cancel()
        dismissWork = nil
        activeOperationID = nil
        let process = runningProcess
        runningProcess = nil
        process?.terminate()
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
