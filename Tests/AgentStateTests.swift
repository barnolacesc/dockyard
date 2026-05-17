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
