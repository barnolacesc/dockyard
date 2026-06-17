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
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, 1_715_961_131, accuracy: 0.001)
    }

    func testFileURLContainsLowercaseUUID() {
        let id = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
        let url = AgentStateFiles.fileURL(for: id)
        XCTAssertTrue(url.path.hasSuffix("agent-state/aabbccdd-1122-3344-5566-778899aabbcc.json"))
    }
}

@MainActor
final class AgentStateStoreTests: XCTestCase {
    private var tempDir: URL!

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

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dockyard-agent-state-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
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
