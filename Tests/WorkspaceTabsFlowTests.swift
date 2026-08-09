// ABOUTME: Content and safety-boundary tests for the passive workspace-tabs tour.

import XCTest
@testable import Dockyard

@MainActor
final class WorkspaceTabsFlowTests: XCTestCase {
    private let localeCodes = ["en", "ca", "de", "es", "sv"]

    func testFlowHasFourManualStepsWithUniqueIDs() {
        let flow = WorkspaceTabsFlow.make()

        XCTAssertEqual(flow.id, "workspace-tabs")
        XCTAssertEqual(flow.steps.count, 4)
        XCTAssertEqual(Set(flow.steps.map(\.id)).count, flow.steps.count)
        for step in flow.steps {
            guard case .manual = step.advance else {
                return XCTFail("step \(step.id) must not auto-advance")
            }
            XCTAssertNil(step.onEnter, "step \(step.id) must not trigger app actions")
        }
    }

    func testFlowHighlightsTabBarThenFinishesCentered() {
        let steps = WorkspaceTabsFlow.make().steps

        XCTAssertTrue(steps.dropLast().allSatisfy {
            $0.anchor?.rawValue == TourAnchorID.workspaceTabBar.rawValue
        })
        XCTAssertNil(steps.last?.anchor)
    }

    func testAllStepCopyKeysAreLocalizedInEverySupportedLocale() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()

        for localeCode in localeCodes {
            let stringsURL = repoRoot
                .appendingPathComponent("Localization/\(localeCode).lproj/Localizable.strings")
            let contents = try String(contentsOf: stringsURL, encoding: .utf8)
            for step in WorkspaceTabsFlow.make().steps {
                XCTAssertTrue(
                    contents.contains("\"\(step.titleKey)\""),
                    "missing \(localeCode) localization: \(step.titleKey)"
                )
                XCTAssertTrue(
                    contents.contains("\"\(step.bodyKey)\""),
                    "missing \(localeCode) localization: \(step.bodyKey)"
                )
            }
        }
    }

    func testCatalogRoutesKnownFlowsAndRejectsUnknownIDs() {
        XCTAssertEqual(TourFlowCatalog.make(flowID: GettingStartedFlow.id)?.id, "getting-started")
        XCTAssertEqual(TourFlowCatalog.make(flowID: WorkspaceTabsFlow.id)?.id, "workspace-tabs")
        XCTAssertNil(TourFlowCatalog.make(flowID: "unknown"))
    }

    func testWhatsNewLinksToWorkspaceTabsFlow() {
        let linkedFlowIDs = WhatsNewCatalog.releases
            .flatMap(\.entries)
            .compactMap(\.tourFlowID)

        XCTAssertTrue(linkedFlowIDs.contains(WorkspaceTabsFlow.id))
    }

    func testWhatsNewCopyIsLocalizedInEverySupportedLocale() throws {
        let entry = try XCTUnwrap(
            WhatsNewCatalog.releases
                .flatMap(\.entries)
                .first { $0.tourFlowID == WorkspaceTabsFlow.id }
        )
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()

        for localeCode in localeCodes {
            let stringsURL = repoRoot
                .appendingPathComponent("Localization/\(localeCode).lproj/Localizable.strings")
            let contents = try String(contentsOf: stringsURL, encoding: .utf8)
            XCTAssertTrue(contents.contains("\"\(entry.titleKey)\""))
            XCTAssertTrue(contents.contains("\"\(entry.bodyKey)\""))
        }
    }
}
