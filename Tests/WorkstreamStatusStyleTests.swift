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
}
