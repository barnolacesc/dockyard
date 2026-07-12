// ABOUTME: Records only the Dockyard window for the automated website product tour.
// ABOUTME: Uses ScreenCaptureKit and writes an H.264 intermediate for deterministic post-processing.

@preconcurrency import AVFoundation
import AppKit
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class RecorderOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let queue = DispatchQueue(label: "dockyard.demo-recorder.writer")
    private var started = false
    private var firstTime: CMTime?

    init(url: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 16_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.writer("cannot add video input") }
        writer.add(input)
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        FileHandle.standardError.write(Data("error: capture stopped: \(error.localizedDescription)\n".utf8))
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        queue.async { [self] in
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !started {
                guard writer.startWriting() else { return }
                firstTime = time
                writer.startSession(atSourceTime: time)
                started = true
            }
            if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
        }
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                input.markAsFinished()
                writer.finishWriting { continuation.resume() }
            }
        }
    }
}

enum RecorderError: LocalizedError {
    case usage, permission, targetProcess, window, writer(String)
    var errorDescription: String? {
        switch self {
        case .usage: return "usage: dockyard-demo-recorder --output PATH --target-pid-file PATH [--duration SECONDS]"
        case .permission: return "Screen Recording permission is missing. Enable it in System Settings > Privacy & Security > Screen Recording."
        case .targetProcess: return "The demo Dockyard process did not publish its PID before the 120-second timeout."
        case .window: return "The demo Dockyard window did not appear before the 120-second timeout."
        case let .writer(message): return "video writer error: \(message)"
        }
    }
}

@main
enum DemoRecorder {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    @MainActor static func run() async throws {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        if args.contains("--request-permission") {
            guard CGRequestScreenCaptureAccess() else { throw RecorderError.permission }
            return
        }
        if args.contains("--check-permissions") {
            let allowed = CGPreflightScreenCaptureAccess()
            if let index = args.firstIndex(of: "--status-file"), args.indices.contains(index + 1) {
                try (allowed ? "allowed\n" : "denied\n").write(
                    toFile: args[index + 1], atomically: true, encoding: .utf8
                )
            }
            guard allowed else { throw RecorderError.permission }
            return
        }
        guard let outputIndex = args.firstIndex(of: "--output"), args.indices.contains(outputIndex + 1) else { throw RecorderError.usage }
        guard let pidFileIndex = args.firstIndex(of: "--target-pid-file"), args.indices.contains(pidFileIndex + 1) else { throw RecorderError.usage }
        let outputURL = URL(fileURLWithPath: args[outputIndex + 1])
        let pidFile = args[pidFileIndex + 1]
        let duration = args.firstIndex(of: "--duration").flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil } ?? 58
        try? FileManager.default.removeItem(at: outputURL)

        guard CGPreflightScreenCaptureAccess() else { throw RecorderError.permission }
        let deadline = Date().addingTimeInterval(120)
        var targetPID: pid_t?
        while Date() < deadline, targetPID == nil {
            if let value = try? String(contentsOfFile: pidFile, encoding: .utf8),
               let pid = pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0
            {
                targetPID = pid
            } else {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        guard let targetPID else { throw RecorderError.targetProcess }
        var window: SCWindow?
        while Date() < deadline, window == nil {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            window = content.windows.first {
                $0.owningApplication?.processID == targetPID
                    && $0.title != nil && $0.frame.width > 800
            }
            if window == nil { try await Task.sleep(for: .milliseconds(250)) }
        }
        guard let window else { throw RecorderError.window }

        let scale = 2
        let width = Int(window.frame.width) * scale
        let height = Int(window.frame.height) * scale
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.backgroundColor = CGColor.black

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let recorder = try RecorderOutput(url: outputURL, width: width, height: height)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "dockyard.demo-recorder.frames"))
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(duration))
        try await stream.stopCapture()
        await recorder.finish()
        if let index = args.firstIndex(of: "--completion-file"), args.indices.contains(index + 1) {
            try "completed\n".write(toFile: args[index + 1], atomically: true, encoding: .utf8)
        }
    }
}
