// ABOUTME: Content, safety, routing, anchor, and localization checks for the power-features tour.

import XCTest
@testable import Dockyard

@MainActor
final class PowerFeaturesFlowTests: XCTestCase {
    private let localeCodes = ["en", "ca", "de", "es", "sv"]

    func testFlowHasSixManualStepsWithUniqueIDs() {
        let flow = PowerFeaturesFlow.make()

        XCTAssertEqual(flow.id, "power-features")
        XCTAssertEqual(flow.steps.count, 6)
        XCTAssertEqual(
            flow.steps.map(\.id),
            ["overview", "shortcut-hints", "usage-meters", "tmux-persistence", "safe-archive", "done"]
        )
        XCTAssertEqual(Set(flow.steps.map(\.id)).count, flow.steps.count)
        for step in flow.steps {
            guard case .manual = step.advance else {
                return XCTFail("step \(step.id) must not auto-advance")
            }
            XCTAssertNil(step.onEnter, "step \(step.id) must not trigger app actions")
        }
    }

    func testFlowHighlightsExistingPowerFeatureSurfaces() {
        let anchors = PowerFeaturesFlow.make().steps.map(\.anchor)

        XCTAssertEqual(
            anchors,
            [nil, .workspaceTabBar, .sidebarStatusStrip, .agentTab, .selectedWorkstreamRow, nil]
        )
    }

    func testCatalogRoutesPowerFeaturesFlow() {
        XCTAssertEqual(TourFlowCatalog.make(flowID: PowerFeaturesFlow.id)?.id, "power-features")
    }

    func testWhatsNewLinksToPowerFeaturesFlow() {
        let linkedFlowIDs = WhatsNewCatalog.releases
            .flatMap(\.entries)
            .compactMap(\.tourFlowID)

        XCTAssertTrue(linkedFlowIDs.contains(PowerFeaturesFlow.id))
    }

    func testAllPowerFeaturesCopyIsLocalizedInEverySupportedLocale() throws {
        let entry = try XCTUnwrap(
            WhatsNewCatalog.releases
                .flatMap(\.entries)
                .first { $0.tourFlowID == PowerFeaturesFlow.id }
        )
        let flow = PowerFeaturesFlow.make()
        let copyKeys = flow.steps.flatMap { [$0.titleKey, $0.bodyKey] }
            + [entry.titleKey, entry.bodyKey]
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()

        for localeCode in localeCodes {
            let stringsURL = repoRoot
                .appendingPathComponent("Localization/\(localeCode).lproj/Localizable.strings")
            let contents = try String(contentsOf: stringsURL, encoding: .utf8)
            for key in copyKeys {
                XCTAssertTrue(
                    contents.contains("\"\(key)\""),
                    "missing \(localeCode) localization: \(key)"
                )
            }
        }
    }
}
