// ABOUTME: Tests for workstream sidebar status-to-visual mapping.

@testable import Dockyard
import XCTest

final class WorkstreamStatusStyleTests: XCTestCase {
    func testWorkingUsesPulsingGreenOrbAndNeutralText() {
        let style = WorkstreamStatusStyle(agentState: .working, isPathValid: true)

        XCTAssertEqual(style.indicatorShape, .circle)
        XCTAssertEqual(style.indicatorColor, .green)
        XCTAssertTrue(style.pulses)
        XCTAssertEqual(style.labelColor, .primary)
        XCTAssertEqual(style.subtitleColor, .tertiary)
        XCTAssertNil(style.rowTintColor)
    }

    func testWaitingUsesStaticBlueOrbLabelSubtitleAndNoTint() {
        let style = WorkstreamStatusStyle(agentState: .waiting, isPathValid: true)

        XCTAssertEqual(style.indicatorShape, .circle)
        XCTAssertEqual(style.indicatorColor, .blue)
        XCTAssertFalse(style.pulses)
        XCTAssertEqual(style.labelColor, .blue)
        XCTAssertEqual(style.subtitleColor, .blue)
        XCTAssertEqual(style.subtitleOpacity, 0.8)
        XCTAssertNil(style.rowTintColor)
        XCTAssertEqual(style.rowTintOpacity, 0)
    }

    func testIdleUsesSmallStaticTertiaryOrbAndNeutralText() {
        let style = WorkstreamStatusStyle(agentState: .idle, isPathValid: true)

        XCTAssertEqual(style.indicatorShape, .circle)
        XCTAssertEqual(style.indicatorColor, .tertiary)
        XCTAssertEqual(style.indicatorSize, 5)
        XCTAssertFalse(style.pulses)
        XCTAssertEqual(style.labelColor, .primary)
        XCTAssertEqual(style.subtitleColor, .tertiary)
        XCTAssertNil(style.rowTintColor)
    }

    func testNilAgentStateDrawsNoOrbAndNeutralText() {
        let style = WorkstreamStatusStyle(agentState: nil, isPathValid: true)

        XCTAssertEqual(style.indicatorShape, .none)
        XCTAssertNil(style.indicatorColor)
        XCTAssertFalse(style.pulses)
        XCTAssertEqual(style.labelColor, .primary)
        XCTAssertEqual(style.subtitleColor, .tertiary)
        XCTAssertNil(style.rowTintColor)
    }

    func testInvalidPathUsesWarningTriangleAndMutedText() {
        let style = WorkstreamStatusStyle(agentState: .waiting, isPathValid: false)

        XCTAssertEqual(style.indicatorShape, .warningTriangle)
        XCTAssertEqual(style.indicatorColor, .orange)
        XCTAssertFalse(style.pulses)
        XCTAssertEqual(style.labelColor, .secondary)
        XCTAssertEqual(style.subtitleColor, .tertiary)
        XCTAssertNil(style.rowTintColor)
    }

    func testSelectedRowsUseSystemSelectedTextForEveryAgentState() {
        let states: [AgentState?] = [.working, .waiting, .idle, nil]

        for state in states {
            let style = WorkstreamRowForegroundStyle(
                statusStyle: WorkstreamStatusStyle(agentState: state, isPathValid: true),
                stageStyle: WorkstreamStageStyle(displayStage: .normal, isManuallySet: false, prNumber: nil),
                isSelected: true
            )

            XCTAssertEqual(style.labelColor, .selected)
            XCTAssertEqual(style.subtitleColor, .selected)
            XCTAssertEqual(style.subtitleOpacity, 1)
            XCTAssertEqual(style.contentOpacity, 1)
        }
    }

    func testSelectedInvalidAndCompletedRowsDoNotReintroduceMutedText() {
        let style = WorkstreamRowForegroundStyle(
            statusStyle: WorkstreamStatusStyle(agentState: .waiting, isPathValid: false),
            stageStyle: WorkstreamStageStyle(displayStage: .done, isManuallySet: false, prNumber: 40),
            isSelected: true
        )

        XCTAssertEqual(style.labelColor, .selected)
        XCTAssertEqual(style.subtitleColor, .selected)
        XCTAssertEqual(style.subtitleOpacity, 1)
        XCTAssertEqual(style.contentOpacity, 1)
    }

    func testUnselectedRowsPreserveStatusAndCompletedRowTreatment() {
        let waiting = WorkstreamRowForegroundStyle(
            statusStyle: WorkstreamStatusStyle(agentState: .waiting, isPathValid: true),
            stageStyle: WorkstreamStageStyle(displayStage: .normal, isManuallySet: false, prNumber: nil),
            isSelected: false
        )
        XCTAssertEqual(waiting.labelColor, .blue)
        XCTAssertEqual(waiting.subtitleColor, .blue)
        XCTAssertEqual(waiting.subtitleOpacity, 0.8)
        XCTAssertEqual(waiting.contentOpacity, 1)

        let completed = WorkstreamRowForegroundStyle(
            statusStyle: WorkstreamStatusStyle(agentState: .working, isPathValid: true),
            stageStyle: WorkstreamStageStyle(displayStage: .done, isManuallySet: false, prNumber: 40),
            isSelected: false
        )
        XCTAssertEqual(completed.labelColor, .secondary)
        XCTAssertEqual(completed.subtitleColor, .secondary)
        XCTAssertEqual(completed.subtitleOpacity, 1)
        XCTAssertEqual(completed.contentOpacity, 0.65)
    }
}
