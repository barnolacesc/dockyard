// ABOUTME: Verifies Coding Agent state transitions become bounded Attention events.
// ABOUTME: Keeps the inbox semantics independent from filesystem observation.

@testable import Dockyard
import XCTest

@MainActor
final class AgentActivityTests: XCTestCase {
    func testMapsAgentStateTransitionsToActivityKinds() {
        let startedID = UUID()
        let waitingID = UUID()
        let completedID = UUID()
        let inactiveID = UUID()
        let removedIdleID = UUID()
        let unchangedID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let events = AgentActivityStore.transitions(
            from: [
                waitingID: .working,
                completedID: .working,
                inactiveID: .waiting,
                removedIdleID: .idle,
                unchangedID: .working,
            ],
            to: [
                startedID: .working,
                waitingID: .waiting,
                completedID: .idle,
                unchangedID: .working,
            ],
            at: date
        )

        let kinds = Dictionary(uniqueKeysWithValues: events.map { ($0.workstreamID, $0.kind) })
        XCTAssertEqual(kinds[startedID], .started)
        XCTAssertEqual(kinds[waitingID], .waiting)
        XCTAssertEqual(kinds[completedID], .completed)
        XCTAssertEqual(kinds[inactiveID], .inactive)
        XCTAssertNil(kinds[removedIdleID])
        XCTAssertNil(kinds[unchangedID])
        XCTAssertEqual(events.map(\.occurredAt), Array(repeating: date, count: 4))
    }
}
