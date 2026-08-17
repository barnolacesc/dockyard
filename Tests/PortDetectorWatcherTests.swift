// ABOUTME: Tests PortDetector filesystem watcher recovery and shutdown behavior.
// ABOUTME: Covers ordinary state updates and replacement of the run-state directory.

@testable import Dockyard
import XCTest

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

    @MainActor
    func testCreatesMissingRunStateDirectoryWithPrivatePermissions() throws {
        try FileManager.default.removeItem(at: root)

        let detector = try makeDetector()
        defer { detector.stop() }

        XCTAssertEqual(try permissions(of: root), 0o700)
    }

    @MainActor
    func testRepairsExistingRunStateDirectoryPermissionsWithoutRemovingState() throws {
        let retainedState = root.appendingPathComponent("retained.json")
        try Data("retained".utf8).write(to: retainedState)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)

        let detector = try makeDetector()
        defer { detector.stop() }

        XCTAssertEqual(try permissions(of: root), 0o700)
        XCTAssertEqual(try Data(contentsOf: retainedState), Data("retained".utf8))
    }

    @MainActor
    func testObservesOrdinaryStateFileReplacement() async throws {
        let detector = try makeDetector()
        defer { detector.stop() }

        try writeState(port: 4100)
        try await waitForPort(4100, from: detector)

        try writeState(port: 4200)
        try await waitForPort(4200, from: detector)
    }

    @MainActor
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
        XCTAssertEqual(try permissions(of: root), 0o700)
    }

    @MainActor
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
            workstreamID: workstreamID,
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

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    @MainActor
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
