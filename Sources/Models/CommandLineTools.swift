// ABOUTME: Resolves full paths for command line tools the app launches directly.
// ABOUTME: Keeps tool detection and process execution consistent across app builds.

import Darwin
import Foundation

struct LoginShellProcessResult: Sendable {
    let output: Data
    let terminationStatus: Int32
    let outputExceededLimit: Bool
}

protocol LoginShellProcess: AnyObject, Sendable {
    var result: LoginShellProcessResult { get }

    func run() throws
    func waitForExit(timeout: TimeInterval) -> Bool
    func terminate()
    func forceTerminate()
}

typealias LoginShellProcessFactory = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ maximumOutputBytes: Int
) throws -> any LoginShellProcess

private let defaultLoginShellProcessFactory: LoginShellProcessFactory = {
    executableURL,
    arguments,
    maximumOutputBytes in
    FoundationLoginShellProcess(
        executableURL: executableURL,
        arguments: arguments,
        maximumOutputBytes: maximumOutputBytes
    )
}

private final class FoundationLoginShellProcess: LoginShellProcess, @unchecked Sendable {
    private let process = Process()
    private let outputPipe = Pipe()
    private let maximumOutputBytes: Int
    private let outputLock = NSLock()
    private var output = Data()
    private var outputExceededLimit = false
    private let outputCondition = NSCondition()
    private var didFinishOutput = false
    private let exitCondition = NSCondition()
    private var didExit = false
    private var terminationStatus: Int32 = -1

    init(executableURL: URL, arguments: [String], maximumOutputBytes: Int) {
        self.maximumOutputBytes = maximumOutputBytes
        process.executableURL = executableURL
        process.arguments = arguments
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

    var result: LoginShellProcessResult {
        let outputDeadline = Date(timeIntervalSinceNow: CommandLineTools.loginShellTerminationGrace)
        outputCondition.lock()
        while !didFinishOutput {
            guard outputCondition.wait(until: outputDeadline) else { break }
        }
        outputCondition.unlock()
        outputPipe.fileHandleForReading.readabilityHandler = nil

        outputLock.lock()
        let capturedOutput = output
        let exceededLimit = outputExceededLimit
        outputLock.unlock()

        exitCondition.lock()
        let status = terminationStatus
        exitCondition.unlock()

        return LoginShellProcessResult(
            output: capturedOutput,
            terminationStatus: status,
            outputExceededLimit: exceededLimit
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
            self.captureOutput(chunk)
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

    private func captureOutput(_ chunk: Data) {
        outputLock.lock()
        let remaining = max(0, maximumOutputBytes - output.count)
        if remaining > 0 {
            output.append(contentsOf: chunk.prefix(remaining))
        }
        if chunk.count > remaining {
            outputExceededLimit = true
        }
        outputLock.unlock()
    }
}

enum CommandLineTools {
    static let loginShellTimeout: TimeInterval = 3
    static let loginShellTerminationGrace: TimeInterval = 0.5
    static let maximumLoginShellOutputBytes = 64 * 1024

    static func path(
        for name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        resolveFromPath: (String, [String: String]) -> String? = { name, environment in
            pathFromEnvironment(named: name, environment: environment)
        },
        resolveFromShellPath: (String) -> String? = { shell in
            loginShellPath(shell: shell)
        }
    ) -> String? {
        // Prefer the user's login shell PATH so we find the same binary
        // their terminal would. GUI apps inherit a minimal PATH from launchd,
        // so we resolve the full login shell PATH first.
        if let shell = environment["SHELL"], !shell.isEmpty,
           let shellPath = resolveFromShellPath(CommandBuilder.resolvedUserShell(environment: ["SHELL": shell]))
        {
            for directory in shellPath.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
                if isExecutable(candidate) {
                    return candidate
                }
            }
        }

        // Fall back to the process PATH (minimal launchd PATH for GUI apps)
        if let found = resolveFromPath(name, environment) {
            return found
        }

        // Last resort: check well-known locations
        let knownLocations = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)",
            "/run/current-system/sw/bin/\(name)",
            "\(NSHomeDirectory())/.nix-profile/bin/\(name)",
        ]

        for location in knownLocations where isExecutable(location) {
            return location
        }

        return nil
    }

    private static let shellPathCache = ShellPathCache()

    static func loginShellPath(shell: String) -> String? {
        shellPathCache.resolve(shell: shell)
    }

    final class ShellPathCache: Sendable {
        private let lock = NSLock()
        private let storage = MutableBox()
        private let processFactory: LoginShellProcessFactory

        /// Mutable state isolated behind NSLock
        private final class MutableBox: @unchecked Sendable {
            var resolved = false
            var path: String?
        }

        convenience init() {
            self.init(processFactory: defaultLoginShellProcessFactory)
        }

        init(processFactory: @escaping LoginShellProcessFactory) {
            self.processFactory = processFactory
        }

        func resolve(shell: String) -> String? {
            lock.lock()
            defer { lock.unlock() }

            if storage.resolved { return storage.path }
            storage.resolved = true

            let process: any LoginShellProcess
            do {
                process = try processFactory(
                    URL(fileURLWithPath: shell),
                    ["-lic", "printenv PATH"],
                    CommandLineTools.maximumLoginShellOutputBytes
                )
                try process.run()
            } catch {
                return nil
            }

            guard process.waitForExit(timeout: CommandLineTools.loginShellTimeout) else {
                process.terminate()
                if !process.waitForExit(timeout: CommandLineTools.loginShellTerminationGrace) {
                    process.forceTerminate()
                    _ = process.waitForExit(timeout: CommandLineTools.loginShellTerminationGrace)
                }
                return nil
            }

            let result = process.result
            guard result.terminationStatus == 0,
                  !result.outputExceededLimit,
                  let path = String(data: result.output, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty
            else { return nil }
            storage.path = path
            return path
        }
    }

    private static func pathFromEnvironment(named name: String, environment: [String: String]) -> String? {
        guard let rawPath = environment["PATH"], !rawPath.isEmpty else { return nil }

        for directory in rawPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}
