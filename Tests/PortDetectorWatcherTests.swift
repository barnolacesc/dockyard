// ABOUTME: Tests PortDetector filesystem watcher recovery and shutdown behavior.
// ABOUTME: Covers ordinary state updates and replacement of the run-state directory.

@testable import Dockyard
import XCTest

@MainActor
final class PortDetectorWatcherTests: XCTestCase {
    private var root: URL!
    private var displacedRoot: URL!
    private var workstreamID: UUID!
    private var stateURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("dy-port-detector-\(UUID().uuidString)", isDirectory: true)
        root = parent.appendingPathComponent("run-state", isDirectory: true)
        displacedRoot = parent.appendingPathComponent("run-state-old", isDirectory: true)
        workstreamID = try XCTUnwrap(UUID(uuidString: "12345678-1234-1234-1234-123456789ABC"))
        stateURL = root.appendingPathComponent("\(workstreamID.uuidString.lowercased()).json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        try super.tearDownWithError()
    }

    func testObservesOrdinaryStateFileReplacement() async throws {
        let detector = try makeDetector()
        defer { detector.stop() }

        try writeState(port: 4100)
        try await waitForPort(4100, from: detector)

        try writeState(port: 4200)
        try await waitForPort(4200, from: detector)
    }

    func testRecoversAfterRunStateDirectoryReplacement() async throws {
        let detector = try makeDetector()
        defer { detector.stop() }

        try writeState(port: 4100)
        try await waitForPort(4100, from: detector)

        try FileManager.default.moveItem(at: root, to: displacedRoot)
        try await waitForPort(nil, from: detector)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeState(port: 4200)

        try await waitForPort(4200, from: detector)
    }

    func testStopCancelsPendingDirectoryRecovery() async throws {
        let detector = try makeDetector(recoveryDelay: .milliseconds(100))

        try writeState(port: 4100)
        try await waitForPort(4100, from: detector)

        try FileManager.default.moveItem(at: root, to: displacedRoot)
        try await waitForPort(nil, from: detector)
        detector.stop()

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeState(port: 4200)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertNil(detector.selectedPort)
    }

    private func makeDetector(recoveryDelay: DispatchTimeInterval = .milliseconds(20)) throws -> PortDetector {
        let stateURL = try XCTUnwrap(stateURL)
        return PortDetector(
            workstreamID: workstreamID,
            directoryURL: root,
            recoveryDelay: recoveryDelay,
            recoveryAttemptLimit: 50,
            loadState: { RunStateStore.load(from: stateURL) }
        )
    }

    private func writeState(port: Int) throws {
        let snapshot = RunStateSnapshot(
            pid: getpid(),
            status: .running,
            detectedPorts: [port],
            selectedPort: port,
            startedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: stateURL, options: .atomic)
    }

    private func waitForPort(
        _ expectedPort: Int?,
        from detector: PortDetector,
        timeout: Duration = .seconds(2)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while detector.selectedPort != expectedPort, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(detector.selectedPort, expectedPort)
    }
}
