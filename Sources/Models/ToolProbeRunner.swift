// ABOUTME: Runs bounded startup probes for locally installed command-line tools.
// ABOUTME: Prevents broken version/help commands from hanging startup or flooding memory.

import Darwin
import Foundation

struct ToolProbeProcessResult: Sendable {
    let output: Data
    let terminationStatus: Int32
    let outputExceededLimit: Bool
}

protocol ToolProbeProcess: AnyObject, Sendable {
    var result: ToolProbeProcessResult { get }

    func run() throws
    func waitForExit(timeout: TimeInterval) -> Bool
    func terminate()
    func forceTerminate()
}

typealias ToolProbeProcessFactory = @Sendable (
    _ executableURL: URL,
    _ arguments: [String],
    _ includeStderr: Bool,
    _ maximumOutputBytes: Int
) throws -> any ToolProbeProcess

let defaultToolProbeProcessFactory: ToolProbeProcessFactory = {
    executableURL,
    arguments,
    includeStderr,
    maximumOutputBytes in
    FoundationToolProbeProcess(
        executableURL: executableURL,
        arguments: arguments,
        includeStderr: includeStderr,
        maximumOutputBytes: maximumOutputBytes
    )
}

private final class FoundationToolProbeProcess: ToolProbeProcess, @unchecked Sendable {
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

    init(
        executableURL: URL,
        arguments: [String],
        includeStderr: Bool,
        maximumOutputBytes: Int
    ) {
        self.maximumOutputBytes = maximumOutputBytes
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = includeStderr ? outputPipe : FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.exitCondition.lock()
            self.terminationStatus = process.terminationStatus
            self.didExit = true
            self.exitCondition.broadcast()
            self.exitCondition.unlock()
        }
    }

    var result: ToolProbeProcessResult {
        let outputDeadline = Date(timeIntervalSinceNow: ToolStatus.probeTerminationGrace)
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

        return ToolProbeProcessResult(
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
        var shouldTerminate = false
        outputLock.lock()
        let remaining = max(0, maximumOutputBytes - output.count)
        if remaining > 0 {
            output.append(contentsOf: chunk.prefix(remaining))
        }
        if chunk.count > remaining {
            outputExceededLimit = true
            shouldTerminate = true
        }
        outputLock.unlock()

        if shouldTerminate {
            terminate()
        }
    }
}
