// ABOUTME: Runs the .dockyard.json `setup` script as a background Process.
// ABOUTME: Captures a tail of stdout/stderr, exposes state for the UI to observe.

import Foundation
import SwiftUI
import os

private let logger = Logger(subsystem: "dockyard", category: "setup-runner")

final class SetupOutputCollector: @unchecked Sendable {
    private let inputLock = NSLock()
    private let stateLock = NSLock()
    private let maximumBytes: Int
    private var pending = Data()
    private var deliveryScheduled = false
    private var isTerminal = false

    init(maximumBytes: Int) {
        self.maximumBytes = max(0, maximumBytes)
    }

    /// Returns true only when the caller needs to schedule a delivery.
    @discardableResult
    func append(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }

        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isTerminal else { return false }

        retainLatest(data)
        guard !deliveryScheduled else { return false }
        deliveryScheduled = true
        return true
    }

    /// Serializes reads from the shared pipe with the completion drain.
    func readAndAppend(from handle: FileHandle, maximumReadBytes: Int) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }

        guard maximumReadBytes > 0,
              let data = try? handle.read(upToCount: maximumReadBytes),
              !data.isEmpty
        else { return false }
        return append(data)
    }

    func drain() -> Data {
        stateLock.lock()
        defer { stateLock.unlock() }

        let output = pending
        pending.removeAll(keepingCapacity: true)
        deliveryScheduled = false
        return output
    }

    func finish(appending finalData: Data = Data()) -> Data? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isTerminal else { return nil }

        retainLatest(finalData)
        isTerminal = true
        deliveryScheduled = false
        let output = pending
        pending.removeAll(keepingCapacity: true)
        return output
    }

    func finish(draining handle: FileHandle, readChunkBytes: Int) -> Data? {
        inputLock.lock()
        defer { inputLock.unlock() }

        if readChunkBytes > 0 {
            while let data = try? handle.read(upToCount: readChunkBytes),
                  !data.isEmpty
            {
                append(data)
            }
        }
        return finish()
    }

    func cancel() {
        stateLock.lock()
        defer { stateLock.unlock() }

        isTerminal = true
        deliveryScheduled = false
        pending.removeAll(keepingCapacity: true)
    }

    private func retainLatest(_ data: Data) {
        guard maximumBytes > 0 else {
            pending.removeAll(keepingCapacity: true)
            return
        }
        if data.count >= maximumBytes {
            pending = Data(data.suffix(maximumBytes))
            return
        }

        pending.append(data)
        if pending.count > maximumBytes {
            pending.removeFirst(pending.count - maximumBytes)
        }
    }
}

@MainActor
final class SetupRunner: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case succeeded
        case failed(exitCode: Int32)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var logTail: String = ""

    private let workstreamID: UUID
    private var process: Process?
    private var outputCollector: SetupOutputCollector?
    private var outputBuffer = Data()
    private static let maxLogBytes = 4096
    nonisolated private static let readChunkBytes = 64 * 1024

    init(workstreamID: UUID) {
        self.workstreamID = workstreamID
    }

    /// Starts the script. No-op if already running or already succeeded.
    func start(script: String, workingDirectory: String, environmentVars: [String: String] = [:], shell: String = CommandBuilder.userShell) {
        if state == .running || state == .succeeded {
            return
        }

        outputBuffer = Data()
        logTail = ""
        state = .running

        let process = Process()
        self.process = process

        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", script]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var env = ProcessInfo.processInfo.environment
        for (k, v) in environmentVars {
            env[k] = v
        }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let outputCollector = SetupOutputCollector(maximumBytes: Self.maxLogBytes)
        self.outputCollector = outputCollector

        let workstreamID = self.workstreamID

        pipe.fileHandleForReading.readabilityHandler = { [weak self, outputCollector] handle in
            guard outputCollector.readAndAppend(
                from: handle,
                maximumReadBytes: SetupRunner.readChunkBytes
            ) else { return }

            Task { @MainActor [weak self, outputCollector] in
                guard let self,
                      self.outputCollector === outputCollector
                else { return }
                self.appendOutput(outputCollector.drain())
            }
        }

        process.terminationHandler = { [weak self, outputCollector] terminatedProcess in
            let exitCode = terminatedProcess.terminationStatus
            guard let outputPipe = terminatedProcess.standardOutput as? Pipe else { return }
            let outputHandle = outputPipe.fileHandleForReading
            outputHandle.readabilityHandler = nil
            guard let remainingOutput = outputCollector.finish(
                draining: outputHandle,
                readChunkBytes: SetupRunner.readChunkBytes
            ) else { return }

            Task { @MainActor [weak self, outputCollector] in
                guard let self,
                      self.outputCollector === outputCollector
                else { return }
                self.appendOutput(remainingOutput)
                if exitCode == 0 {
                    self.state = .succeeded
                    SetupStateStore.markCompleted(for: workstreamID)
                } else {
                    self.state = .failed(exitCode: exitCode)
                }
                self.process = nil
                self.outputCollector = nil
            }
        }

        do {
            try process.run()
        } catch {
            outputCollector.cancel()
            state = .failed(exitCode: -1)
            logTail = error.localizedDescription
            self.process = nil
            self.outputCollector = nil
        }
    }

    private func appendOutput(_ data: Data) {
        guard !data.isEmpty else { return }

        outputBuffer.append(data)
        if outputBuffer.count > Self.maxLogBytes {
            outputBuffer.removeFirst(outputBuffer.count - Self.maxLogBytes)
        }
        logTail = String(decoding: outputBuffer, as: UTF8.self)
    }

    /// Terminates the running process if any. State becomes .idle.
    func cancel() {
        guard let process = process else { return }

        if let pipe = process.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        outputCollector?.cancel()

        if process.isRunning {
            process.terminate()
        }

        state = .idle
        self.process = nil
        outputCollector = nil
    }
}
