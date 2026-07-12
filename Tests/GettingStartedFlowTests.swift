// ABOUTME: Content sanity checks for the Getting Started tour flow.

import XCTest
@testable import Dockyard

@MainActor
final class GettingStartedFlowTests: XCTestCase {
    func testFlowHasNineStepsWithUniqueIDs() {
        let flow = GettingStartedFlow.make()
        XCTAssertEqual(flow.id, "getting-started")
        XCTAssertEqual(flow.steps.count, 9)
        XCTAssertEqual(Set(flow.steps.map(\.id)).count, flow.steps.count)
    }

    func testAllStepsHaveNonEmptyCopyKeys() {
        for step in GettingStartedFlow.make().steps {
            XCTAssertFalse(step.titleKey.isEmpty, "step \(step.id) has empty title")
            XCTAssertFalse(step.bodyKey.isEmpty, "step \(step.id) has empty body")
        }
    }

    func testFirstAndLastStepsAreCenteredCards() {
        let steps = GettingStartedFlow.make().steps
        XCTAssertNil(steps.first?.anchor)
        XCTAssertNil(steps.last?.anchor)
    }

    func testEveryStepCopyKeyIsLocalizedInEnglish() throws {
        // Resolve the repo's en strings file relative to this test file.
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let stringsURL = repoRoot
            .appendingPathComponent("Localization/en.lproj/Localizable.strings")
        let contents = try String(contentsOf: stringsURL, encoding: .utf8)
        for step in GettingStartedFlow.make().steps {
            XCTAssertTrue(contents.contains("\"\(step.titleKey)\""), "missing en localization: \(step.titleKey)")
            XCTAssertTrue(contents.contains("\"\(step.bodyKey)\""), "missing en localization: \(step.bodyKey)")
        }
    }
}
