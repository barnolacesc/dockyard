// ABOUTME: Tests caffeinate mode policy without changing the host Mac's sleep settings.
// ABOUTME: Covers disabled, agent-aware, and always-on behavior.

@testable import Dockyard
import XCTest

final class CaffeinateControllerTests: XCTestCase {
    private let workstreamID = UUID()

    func testOffNeverPreventsSleep() async {
        let result = await CaffeinateController.shouldPreventSleep(
            mode: .off,
            states: [workstreamID: .working]
        )

        XCTAssertFalse(result)
    }

    func testAgentModePreventsSleepOnlyWhileAnAgentIsWorking() async {
        let working = await CaffeinateController.shouldPreventSleep(
            mode: .whileAgentsWork,
            states: [workstreamID: .working]
        )
        let waiting = await CaffeinateController.shouldPreventSleep(
            mode: .whileAgentsWork,
            states: [workstreamID: .waiting]
        )
        let idle = await CaffeinateController.shouldPreventSleep(
            mode: .whileAgentsWork,
            states: [workstreamID: .idle]
        )

        XCTAssertTrue(working)
        XCTAssertFalse(waiting)
        XCTAssertFalse(idle)
    }

    func testAlwaysPreventsSleepWithoutActiveAgents() async {
        let result = await CaffeinateController.shouldPreventSleep(mode: .always, states: [:])

        XCTAssertTrue(result)
    }
}
