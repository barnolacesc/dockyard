// ABOUTME: Tests for run-script port detection and browser retargeting behavior.
// ABOUTME: Covers launcher command building, port selection stabilization, and browser navigation policy.

@testable import Dockyard
import XCTest

final class PortDetectionTests: XCTestCase {
    func testRunLauncherWrapsRunScriptInLoginShell() throws {
        let workstreamID = try XCTUnwrap(UUID(uuidString: "12345678-1234-1234-1234-123456789ABC"))

        let command = runScriptCommand(
            script: "just dev",
            workstreamID: workstreamID,
            launcherPath: "/Applications/Dockyard.app/Contents/Helpers/dy-run",
            shell: "/bin/zsh"
        )

        XCTAssertEqual(
            command,
            "/Applications/Dockyard.app/Contents/Helpers/dy-run --workstream-id 12345678-1234-1234-1234-123456789abc -- /bin/zsh -lic 'just dev'"
        )
    }

    func testValidatedRunStateAcceptsActiveMatchingProcess() throws {
        let workstreamID = UUID()
        defer { RunStateStore.remove(for: workstreamID) }
        let processStart = try XCTUnwrap(RunStateStore.processStartDate(pid: getpid()))
        try RunStateStore.write(
            runState(
                workstreamID: workstreamID,
                pid: getpid(),
                status: .running,
                selectedPort: 5173,
                startedAt: processStart
            ),
            for: workstreamID
        )

        let state = try XCTUnwrap(RunStateStore.loadValidated(for: workstreamID))

        XCTAssertEqual(state.selectedPort, 5173)
        XCTAssertEqual(state.workstreamID, workstreamID)
    }

    func testValidatedRunStateRejectsDeadProcess() throws {
        let workstreamID = UUID()
        defer { RunStateStore.remove(for: workstreamID) }
        try RunStateStore.write(
            runState(
                workstreamID: workstreamID,
                pid: Int32.max,
                status: .running,
                selectedPort: 5173
            ),
            for: workstreamID
        )

        XCTAssertNil(RunStateStore.loadValidated(for: workstreamID))
    }

    func testValidatedRunStateRejectsReusedProcessIdentifier() throws {
        let workstreamID = UUID()
        defer { RunStateStore.remove(for: workstreamID) }
        let processStart = try XCTUnwrap(RunStateStore.processStartDate(pid: getpid()))
        try RunStateStore.write(
            runState(
                workstreamID: workstreamID,
                pid: getpid(),
                status: .running,
                selectedPort: 5173,
                startedAt: processStart.addingTimeInterval(-60)
            ),
            for: workstreamID
        )

        XCTAssertNil(RunStateStore.loadValidated(for: workstreamID))
    }

    func testValidatedRunStateRejectsMismatchedWorkstream() throws {
        let requestedID = UUID()
        defer { RunStateStore.remove(for: requestedID) }
        let processStart = try XCTUnwrap(RunStateStore.processStartDate(pid: getpid()))
        try RunStateStore.write(
            runState(
                workstreamID: UUID(),
                pid: getpid(),
                status: .running,
                selectedPort: 5173,
                startedAt: processStart
            ),
            for: requestedID
        )

        XCTAssertNil(RunStateStore.loadValidated(for: requestedID))
    }

    func testValidatedRunStateRejectsStoppedStateForLiveProcess() throws {
        let workstreamID = UUID()
        defer { RunStateStore.remove(for: workstreamID) }
        let processStart = try XCTUnwrap(RunStateStore.processStartDate(pid: getpid()))
        try RunStateStore.write(
            runState(
                workstreamID: workstreamID,
                pid: getpid(),
                status: .stopped,
                selectedPort: 5173,
                startedAt: processStart
            ),
            for: workstreamID
        )

        XCTAssertNil(RunStateStore.loadValidated(for: workstreamID))
    }

    func testValidatedRunStateRejectsMalformedJSON() throws {
        let workstreamID = UUID()
        defer { RunStateStore.remove(for: workstreamID) }
        try FileManager.default.createDirectory(
            at: RunStateStore.directoryURL,
            withIntermediateDirectories: true
        )
        try Data("{not-json".utf8).write(
            to: RunStateStore.fileURL(for: workstreamID),
            options: .atomic
        )

        XCTAssertNil(RunStateStore.loadValidated(for: workstreamID))
    }

    func testSingleNewPortRequiresTwoPollsBeforeSelection() {
        var tracker = PortSelectionTracker(expectedPort: 40001)

        let first = tracker.update(listeningPorts: [5173])
        XCTAssertEqual(first.detectedPorts, [5173])
        XCTAssertNil(first.selectedPort)

        let second = tracker.update(listeningPorts: [5173])
        XCTAssertEqual(second.selectedPort, 5173)
    }

    func testMultiplePortsPreferExpectedPort() {
        var tracker = PortSelectionTracker(expectedPort: 40001)
        _ = tracker.update(listeningPorts: [40001, 5173])

        let second = tracker.update(listeningPorts: [40001, 5173])

        XCTAssertEqual(second.detectedPorts, [40001, 5173])
        XCTAssertEqual(second.selectedPort, 40001)
    }

    func testMultiplePortsWithoutExpectedPortDoNotAutoSelect() {
        var tracker = PortSelectionTracker(expectedPort: 40001)
        _ = tracker.update(listeningPorts: [3000, 5173])

        let second = tracker.update(listeningPorts: [3000, 5173])

        XCTAssertEqual(second.detectedPorts, [3000, 5173])
        XCTAssertNil(second.selectedPort)
    }

    func testBrowserRetargetsWhenStillOnPreviousDefaultURL() {
        XCTAssertTrue(shouldRetargetBrowser(
            currentURL: "http://localhost:40001/",
            displayedURL: "http://localhost:40001/",
            previousDefaultURL: "http://localhost:40001/",
            nextDefaultURL: "http://localhost:5173/",
            connectionError: false
        ))
    }

    func testBrowserRetargetsWhenShowingConnectionErrorForPreviousDefaultURL() {
        XCTAssertTrue(shouldRetargetBrowser(
            currentURL: nil,
            displayedURL: "http://localhost:40001/",
            previousDefaultURL: "http://localhost:40001/",
            nextDefaultURL: "http://localhost:5173/",
            connectionError: true
        ))
    }

    func testBrowserDoesNotRetargetWhenUserNavigatedElsewhere() {
        XCTAssertFalse(shouldRetargetBrowser(
            currentURL: "https://example.com/",
            displayedURL: "https://example.com/",
            previousDefaultURL: "http://localhost:40001/",
            nextDefaultURL: "http://localhost:5173/",
            connectionError: false
        ))
    }

    func testInferExpectedPortFromRunCommand() {
        XCTAssertEqual(RunLauncher.inferExpectedPort(runCommand: "python3 -m flask run --port 5001", projectDirectory: "/tmp"), 5001)
        XCTAssertEqual(RunLauncher.inferExpectedPort(runCommand: "next dev -p 3000", projectDirectory: "/tmp"), 3000)
        XCTAssertEqual(RunLauncher.inferExpectedPort(runCommand: "uvicorn app:app --port 8000", projectDirectory: "/tmp"), 8000)
        XCTAssertEqual(RunLauncher.inferExpectedPort(runCommand: "PORT=8080 node server.js", projectDirectory: "/tmp"), 8080)
        XCTAssertNil(RunLauncher.inferExpectedPort(runCommand: "npm run start", projectDirectory: "/tmp"))
    }

    func testInferExpectedPortFromEnvFile() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let envURL = tempDir.appendingPathComponent(".env")
        try? "PORT=7777".write(to: envURL, atomically: true, encoding: .utf8)
        
        XCTAssertEqual(RunLauncher.inferExpectedPort(runCommand: "npm run start", projectDirectory: tempDir.path), 7777)
    }

    private func runState(
        workstreamID: UUID,
        pid: Int32,
        status: RunStateStatus,
        selectedPort: Int?,
        startedAt: Date = Date()
    ) -> RunStateSnapshot {
        RunStateSnapshot(
            workstreamID: workstreamID,
            pid: pid,
            status: status,
            detectedPorts: selectedPort.map { [$0] } ?? [],
            selectedPort: selectedPort,
            startedAt: startedAt
        )
    }
}
