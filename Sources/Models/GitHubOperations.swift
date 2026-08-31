// ABOUTME: GitHub operations using the gh CLI.
// ABOUTME: Fetches repo info, PRs, and branch-specific PR status.

import Darwin
import Foundation

struct GitHubRepoInfo {
    let name: String
    let url: String
    let description: String?
    let stars: Int
    let forks: Int
    let openIssues: Int
}

struct GitHubPR: Equatable, Sendable {
    let number: Int
    let title: String
    let state: String
    let branch: String
    let url: String
}

enum GitHubPRLookupResult: Equatable, Sendable {
    case found(GitHubPR)
    case notFound
    case unavailable
}

struct GitHubReadProcessResult: Sendable {
    let output: Data
    let terminationStatus: Int32
    let outputExceededLimit: Bool
    let didFinishOutput: Bool
}

final class GitHubReadOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumOutputBytes: Int
    private var output = Data()
    private var outputExceededLimit = false

    init(maximumOutputBytes: Int) {
        self.maximumOutputBytes = max(0, maximumOutputBytes)
    }

    /// Retains at most the configured cap while allowing every delivered chunk to be drained.
    /// Returns true after any bytes have exceeded the cap.
    func ingest(_ chunk: Data) -> Bool {
        lock.withLock {
            let remaining = max(0, maximumOutputBytes - output.count)
            if remaining > 0 {
                output.append(contentsOf: chunk.prefix(remaining))
            }
            if chunk.count > remaining {
                outputExceededLimit = true
            }
            return outputExceededLimit
        }
    }

    var snapshot: (output: Data, outputExceededLimit: Bool) {
        lock.withLock { (output, outputExceededLimit) }
    }
}

protocol GitHubReadProcess: AnyObject, Sendable {
    var result: GitHubReadProcessResult { get }

    func run() throws
    func waitForExit(timeout: TimeInterval) -> Bool
    func terminate()
    func forceTerminate()
}

typealias GitHubReadProcessFactory = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ workingDirectoryURL: URL,
    _ maximumOutputBytes: Int
) throws -> any GitHubReadProcess

private final class FoundationGitHubReadProcess: GitHubReadProcess, @unchecked Sendable {
    private let process = Process()
    private let outputPipe = Pipe()
    private let collector: GitHubReadOutputCollector
    private let outputCondition = NSCondition()
    private var didFinishOutput = false
    private let exitCondition = NSCondition()
    private var didExit = false
    private var terminationStatus: Int32 = -1

    init(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        maximumOutputBytes: Int
    ) {
        collector = GitHubReadOutputCollector(maximumOutputBytes: maximumOutputBytes)
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.exitCondition.lock()
            self.terminationStatus = process.terminationStatus
            self.didExit = true
            self.exitCondition.broadcast()
            self.exitCondition.unlock()
        }
    }

    var result: GitHubReadProcessResult {
        let outputDeadline = Date(timeIntervalSinceNow: GitHubOperations.probeTerminationGrace)
        outputCondition.lock()
        while !didFinishOutput {
            guard outputCondition.wait(until: outputDeadline) else { break }
        }
        let finishedOutput = didFinishOutput
        outputCondition.unlock()
        outputPipe.fileHandleForReading.readabilityHandler = nil

        let snapshot = collector.snapshot
        exitCondition.lock()
        let status = terminationStatus
        exitCondition.unlock()

        return GitHubReadProcessResult(
            output: snapshot.output,
            terminationStatus: status,
            outputExceededLimit: snapshot.outputExceededLimit,
            didFinishOutput: finishedOutput
        )
    }

    func run() throws {
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                self.outputCondition.lock()
                self.didFinishOutput = true
                self.outputCondition.broadcast()
                self.outputCondition.unlock()
                return
            }
            if self.collector.ingest(chunk), self.process.isRunning {
                self.process.terminate()
            }
        }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    func waitForExit(timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        exitCondition.lock()
        defer { exitCondition.unlock() }
        while !didExit {
            guard exitCondition.wait(until: deadline) else { return didExit }
        }
        return true
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    func forceTerminate() {
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }
}

let defaultGitHubReadProcessFactory: GitHubReadProcessFactory = {
    executableURL,
    arguments,
    workingDirectoryURL,
    maximumOutputBytes in
    FoundationGitHubReadProcess(
        executableURL: executableURL,
        arguments: arguments,
        workingDirectoryURL: workingDirectoryURL,
        maximumOutputBytes: maximumOutputBytes
    )
}

enum GitHubOperations {
    static let probeTimeout: TimeInterval = 10
    static let probeTerminationGrace: TimeInterval = 1
    static let maximumProbeOutputBytes = 256 * 1024

    private static var gitPath: String? {
        CommandLineTools.path(for: "git")
    }

    /// Check if the project has a GitHub remote.
    static func hasGitHubRemote(at path: String) -> Bool {
        guard let gitPath,
              let remote = runCommand(gitPath, args: ["remote", "get-url", "origin"], in: path) else { return false }
        return remote.contains("github.com")
    }

    /// Convert a git remote URL to a browser-openable HTTPS URL.
    /// Handles SSH (`git@github.com:owner/repo.git`),
    /// HTTPS (`https://github.com/owner/repo.git`),
    /// and SSH protocol (`ssh://git@github.com/owner/repo.git`) formats.
    static func browserURL(from remoteURL: String) -> URL? {
        var cleaned = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(4))
        }
        // SSH shorthand: git@github.com:owner/repo
        if let atIndex = cleaned.firstIndex(of: "@"),
           let colonIndex = cleaned.firstIndex(of: ":"),
           colonIndex > atIndex,
           !cleaned.hasPrefix("https://"),
           !cleaned.hasPrefix("ssh://")
        {
            let host = cleaned[cleaned.index(after: atIndex) ..< colonIndex]
            let path = cleaned[cleaned.index(after: colonIndex)...]
            return URL(string: "https://\(host)/\(path)")
        }
        // ssh://git@github.com/owner/repo
        if cleaned.hasPrefix("ssh://") {
            cleaned = cleaned.replacingOccurrences(of: "ssh://", with: "https://")
            if let atIndex = cleaned.firstIndex(of: "@") {
                cleaned = "https://" + cleaned[cleaned.index(after: atIndex)...]
            }
            return URL(string: cleaned)
        }
        // Already HTTPS
        if cleaned.hasPrefix("https://") || cleaned.hasPrefix("http://") {
            return URL(string: cleaned)
        }
        return nil
    }

    /// Fetch repo info via gh CLI.
    static func repoInfo(ghPath: String, at path: String) -> GitHubRepoInfo? {
        guard let json = runCommand(ghPath, args: ["repo", "view", "--json", "name,url,description,stargazerCount,forkCount,openIssueCount"], in: path) else { return nil }
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        return GitHubRepoInfo(
            name: dict["name"] as? String ?? "",
            url: dict["url"] as? String ?? "",
            description: dict["description"] as? String,
            stars: dict["stargazerCount"] as? Int ?? 0,
            forks: dict["forkCount"] as? Int ?? 0,
            openIssues: dict["openIssueCount"] as? Int ?? 0
        )
    }

    /// Fetch open PRs for this repo.
    static func openPRs(ghPath: String, at path: String, limit: Int = 5) -> [GitHubPR] {
        guard let json = runCommand(ghPath, args: ["pr", "list", "--json", "number,title,state,headRefName,url", "--limit", "\(limit)"], in: path) else { return [] }
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return array.compactMap { dict in
            guard let number = dict["number"] as? Int,
                  let title = dict["title"] as? String,
                  let state = dict["state"] as? String,
                  let branch = dict["headRefName"] as? String,
                  let url = dict["url"] as? String else { return nil }
            return GitHubPR(number: number, title: title, state: state, branch: branch, url: url)
        }
    }

    /// Find an open PR for a specific branch.
    static func prForBranch(ghPath: String, at path: String, branch: String) -> GitHubPR? {
        guard let json = runCommand(ghPath, args: ["pr", "list", "--head", branch, "--json", "number,title,state,headRefName,url", "--limit", "1"], in: path) else { return nil }
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let dict = array.first else { return nil }

        guard let number = dict["number"] as? Int,
              let title = dict["title"] as? String,
              let state = dict["state"] as? String,
              let branch = dict["headRefName"] as? String,
              let url = dict["url"] as? String else { return nil }
        return GitHubPR(number: number, title: title, state: state, branch: branch, url: url)
    }

    /// Find a merged PR for a specific branch.
    static func mergedPRForBranch(ghPath: String, at path: String, branch: String) -> GitHubPR? {
        guard case let .found(pr) = mergedPRLookupForBranch(
            ghPath: ghPath,
            at: path,
            branch: branch
        ) else { return nil }
        return pr
    }

    /// Distinguish a branch with no merged PR from a failed/unavailable lookup.
    static func mergedPRLookupForBranch(
        ghPath: String,
        at path: String,
        branch: String
    ) -> GitHubPRLookupResult {
        guard let json = runCommand(ghPath, args: ["pr", "list", "--head", branch, "--state", "merged", "--json", "number,title,state,headRefName,url", "--limit", "1"], in: path) else {
            return .unavailable
        }
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return .unavailable }

        guard let dict = array.first else { return .notFound }

        guard let number = dict["number"] as? Int,
              let title = dict["title"] as? String,
              let state = dict["state"] as? String,
              let branch = dict["headRefName"] as? String,
              let url = dict["url"] as? String else { return .unavailable }
        return .found(GitHubPR(number: number, title: title, state: state, branch: branch, url: url))
    }

    static func runCommand(
        _ command: String,
        args: [String],
        in directory: String,
        processFactory: GitHubReadProcessFactory = defaultGitHubReadProcessFactory
    ) -> String? {
        let process: any GitHubReadProcess
        do {
            process = try processFactory(
                URL(fileURLWithPath: command),
                args,
                URL(fileURLWithPath: directory),
                maximumProbeOutputBytes
            )
            try process.run()
        } catch {
            return nil
        }

        guard process.waitForExit(timeout: probeTimeout) else {
            process.terminate()
            if !process.waitForExit(timeout: probeTerminationGrace) {
                process.forceTerminate()
                _ = process.waitForExit(timeout: probeTerminationGrace)
            }
            return nil
        }

        let result = process.result
        guard result.terminationStatus == 0,
              result.didFinishOutput,
              !result.outputExceededLimit,
              let output = String(data: result.output, encoding: .utf8)
        else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
