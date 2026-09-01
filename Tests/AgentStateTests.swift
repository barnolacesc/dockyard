// ABOUTME: Tests for AgentState enum and AgentStateSnapshot Codable round-trip.

@testable import Dockyard
import XCTest

final class AgentStateTests: XCTestCase {
    func testAgentStateRawValues() {
        XCTAssertEqual(AgentState.working.rawValue, "working")
        XCTAssertEqual(AgentState.waiting.rawValue, "waiting")
        XCTAssertEqual(AgentState.idle.rawValue, "idle")
    }

    func testSnapshotRoundTrip() throws {
        let snapshot = AgentStateSnapshot(
            state: .working,
            updatedAt: Date(timeIntervalSince1970: 1_715_961_131),
            pid: 48211
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentStateSnapshot.self, from: data)

        XCTAssertEqual(decoded.state, .working)
        XCTAssertEqual(decoded.pid, 48211)
        XCTAssertFalse(decoded.chromeActive)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, 1_715_961_131, accuracy: 0.001)
    }

    func testFileURLContainsLowercaseUUID() {
        let id = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
        let url = AgentStateFiles.fileURL(for: id)
        XCTAssertTrue(url.path.hasSuffix("agent-state/aabbccdd-1122-3344-5566-778899aabbcc.json"))
    }

    func testSnapshotDecodesLegacyStateFileWithoutChromeActivity() throws {
        let data = Data("{\"pid\":48211,\"state\":\"working\",\"updatedAt\":\"2024-05-17T12:05:31Z\"}".utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(AgentStateSnapshot.self, from: data)

        XCTAssertFalse(snapshot.chromeActive)
    }

    func testSubagentHookInputDecodesOnlyBoundedLifecycleFields() throws {
        let data = Data(#"{"hook_event_name":"SubagentStart","agent_id":"agent-123","agent_type":"Explore","last_assistant_message":"ignored"}"#.utf8)

        XCTAssertEqual(
            AgentSubagentHookInput.decodeValidated(from: data),
            AgentSubagentHookInput(agentID: "agent-123", agentType: "Explore")
        )
        XCTAssertNil(AgentSubagentHookInput.decodeValidated(from: Data()))
        XCTAssertNil(AgentSubagentHookInput.decodeValidated(from: Data(repeating: 0x61, count: AgentSubagentHookInput.maximumInputBytes + 1)))
        XCTAssertNil(AgentSubagentHookInput.decodeValidated(
            from: Data(#"{"agent_id":"agent\n123","agent_type":"Explore"}"#.utf8)
        ))
    }

    func testSubagentFileNameDoesNotExposeUntrustedAgentIDAsAPath() throws {
        let workstreamID = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
        let directory = URL(fileURLWithPath: "/tmp/agent-state", isDirectory: true)
        let url = try XCTUnwrap(AgentSubagentFiles.fileURL(
            for: workstreamID,
            agentID: "agent/../../outside",
            directoryURL: directory
        ))

        XCTAssertEqual(url.deletingLastPathComponent(), directory)
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("aabbccdd-1122-3344-5566-778899aabbcc--"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".subagent.json"))
    }

    func testSubagentFilesUpdateIndependentlyAndCleanupIsWorkstreamScoped() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-subagent-file-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let firstWorkstream = UUID()
        let secondWorkstream = UUID()
        let first = AgentSubagentSnapshot(
            workstreamID: firstWorkstream,
            agentID: "agent-one",
            agentType: "Explore",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            pid: 101
        )
        let second = AgentSubagentSnapshot(
            workstreamID: secondWorkstream,
            agentID: "agent-two",
            agentType: "Plan",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_001),
            pid: 102
        )

        try AgentSubagentFiles.write(first, directoryURL: directory)
        try AgentSubagentFiles.write(second, directoryURL: directory)
        let firstURL = try XCTUnwrap(AgentSubagentFiles.fileURL(
            for: firstWorkstream,
            agentID: first.agentID,
            directoryURL: directory
        ))
        XCTAssertEqual(AgentSubagentFiles.load(from: firstURL), first)

        AgentSubagentFiles.removeAll(for: firstWorkstream, directoryURL: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        let secondURL = try XCTUnwrap(AgentSubagentFiles.fileURL(
            for: secondWorkstream,
            agentID: second.agentID,
            directoryURL: directory
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testSubagentSnapshotAtNoncanonicalFilenameIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-subagent-canonical-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = AgentSubagentSnapshot(
            workstreamID: UUID(),
            agentID: "agent-one",
            agentType: "Explore",
            updatedAt: Date(),
            pid: Int32(getpid())
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let spoofedURL = directory.appendingPathComponent("spoofed.subagent.json")
        try encoder.encode(snapshot).write(to: spoofedURL)

        XCTAssertNil(AgentSubagentFiles.load(from: spoofedURL))
    }
}

@MainActor
final class AgentStateStoreTests: XCTestCase {
    private var tempDir: URL!

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func writeSnapshot(_ state: AgentState, pid: Int32, updatedAt: Date = Date(), for id: UUID) throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let snapshot = AgentStateSnapshot(state: state, updatedAt: updatedAt, pid: pid)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        
        let fileURL = tempDir.appendingPathComponent("\(id.uuidString.lowercased()).json")
        try data.write(to: fileURL, options: .atomic)
    }

    private func writeSubagent(
        workstreamID: UUID,
        agentID: String,
        pid: Int32
    ) throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try AgentSubagentFiles.write(
            AgentSubagentSnapshot(
                workstreamID: workstreamID,
                agentID: agentID,
                agentType: "Explore",
                updatedAt: Date(),
                pid: pid
            ),
            directoryURL: tempDir
        )
    }

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dockyard-agent-state-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCreatesMissingStateDirectoryWithPrivatePermissions() throws {
        let store = AgentStateStore(directoryURL: tempDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
        XCTAssertEqual(try permissions(of: tempDir), 0o700)
        _ = store
    }

    func testRepairsExistingStateDirectoryPermissionsWithoutRemovingState() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let retainedState = tempDir.appendingPathComponent("retained.txt")
        try Data("retained".utf8).write(to: retainedState)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)

        let store = AgentStateStore(directoryURL: tempDir)

        XCTAssertEqual(try permissions(of: tempDir), 0o700)
        XCTAssertEqual(try Data(contentsOf: retainedState), Data("retained".utf8))
        _ = store
    }

    func testInitialScanLoadsExistingFiles() throws {
        let id = UUID()
        try writeSnapshot(.working, pid: Int32(getpid()), for: id)

        let store = AgentStateStore(directoryURL: tempDir)
        store.refresh()

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(store.agentState(for: id), .working)
    }

    func testReturnsUnknownForStalePid() throws {
        let id = UUID()
        // pid 1 is launchd; always alive. Use a clearly dead pid instead.
        try writeSnapshot(.working, pid: Int32(99999), for: id)

        let store = AgentStateStore(directoryURL: tempDir)
        store.refresh()

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNil(store.agentState(for: id))
    }

    func testReturnsNilForUnknownID() {
        let store = AgentStateStore(directoryURL: tempDir)
        XCTAssertNil(store.agentState(for: UUID()))
    }

    func testReportsChromeActivityForLiveSnapshot() throws {
        let id = UUID()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let snapshot = AgentStateSnapshot(state: .working, updatedAt: Date(), pid: Int32(getpid()), chromeActive: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: tempDir.appendingPathComponent("\(id.uuidString.lowercased()).json"))

        let store = AgentStateStore(directoryURL: tempDir)
        store.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(store.isChromeActive(for: id))
    }

    func testActiveSubagentPromotesIdleWorkstreamToWorking() throws {
        let id = UUID()
        try writeSnapshot(.idle, pid: Int32(getpid()), for: id)
        try writeSubagent(workstreamID: id, agentID: "agent-one", pid: Int32(getpid()))
        try writeSubagent(workstreamID: id, agentID: "agent-two", pid: Int32(getpid()))

        let store = AgentStateStore(directoryURL: tempDir)
        store.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(store.agentState(for: id), .working)
        XCTAssertEqual(store.activeSubagentCount(for: id), 2)
    }

    func testWaitingMainAgentRemainsActionableWhileSubagentRuns() throws {
        let id = UUID()
        try writeSnapshot(.waiting, pid: Int32(getpid()), for: id)
        try writeSubagent(workstreamID: id, agentID: "agent-one", pid: Int32(getpid()))

        let store = AgentStateStore(directoryURL: tempDir)
        store.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(store.agentState(for: id), .waiting)
        XCTAssertEqual(store.activeSubagentCount(for: id), 1)
    }

    func testStaleSubagentProcessDoesNotAffectWorkstreamState() throws {
        let id = UUID()
        try writeSnapshot(.idle, pid: Int32(getpid()), for: id)
        try writeSubagent(workstreamID: id, agentID: "agent-one", pid: 99999)

        let store = AgentStateStore(directoryURL: tempDir)
        store.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(store.agentState(for: id), .idle)
        XCTAssertEqual(store.activeSubagentCount(for: id), 0)
    }

    func testWatcherReattachesAfterDirectoryReplacement() throws {
        let id = UUID()
        let store = AgentStateStore(directoryURL: tempDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
        try FileManager.default.removeItem(at: tempDir)

        XCTAssertTrue(waitUntil {
            FileManager.default.fileExists(atPath: self.tempDir.path)
        })
        XCTAssertEqual(try permissions(of: tempDir), 0o700)

        try writeSnapshot(.waiting, pid: Int32(getpid()), for: id)

        XCTAssertTrue(waitUntil {
            store.agentState(for: id) == .waiting
        })
        XCTAssertEqual(store.agentState(for: id), .waiting)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    func testDecaysWorkingOlderThanThirtyMinutesToIdle() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = AgentStateSnapshot(
            state: .working,
            updatedAt: now.addingTimeInterval(-31 * 60),
            pid: Int32(getpid())
        )

        XCTAssertEqual(AgentStateStore.decayedState(snapshot, now: now), .idle)
    }

    func testKeepsRecentWorkingState() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = AgentStateSnapshot(
            state: .working,
            updatedAt: now.addingTimeInterval(-5 * 60),
            pid: Int32(getpid())
        )

        XCTAssertEqual(AgentStateStore.decayedState(snapshot, now: now), .working)
    }

    func testKeepsWaitingAfterThirtyOneMinutes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = AgentStateSnapshot(
            state: .waiting,
            updatedAt: now.addingTimeInterval(-31 * 60),
            pid: Int32(getpid())
        )

        XCTAssertEqual(AgentStateStore.decayedState(snapshot, now: now), .waiting)
    }

    func testDecaysWaitingOlderThanTwoHoursToIdle() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = AgentStateSnapshot(
            state: .waiting,
            updatedAt: now.addingTimeInterval(-3 * 60 * 60),
            pid: Int32(getpid())
        )

        XCTAssertEqual(AgentStateStore.decayedState(snapshot, now: now), .idle)
    }
}
