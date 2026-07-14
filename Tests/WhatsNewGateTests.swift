// ABOUTME: Tests for the What's New version gate: fresh installs, updates, semver compare.

import XCTest
@testable import Dockyard

final class WhatsNewGateTests: XCTestCase {
    private func release(_ version: String) -> WhatsNewRelease {
        WhatsNewRelease(version: version, entries: [
            WhatsNewEntry(symbol: "sparkles", titleKey: "t", bodyKey: "b", tourFlowID: nil),
        ])
    }

    func testFreshInstallShowsNothing() {
        let result = WhatsNewGate.releasesToPresent(
            current: "0.3.0", lastSeen: nil, catalog: [release("0.3.0")]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testSameVersionShowsNothing() {
        let result = WhatsNewGate.releasesToPresent(
            current: "0.3.0", lastSeen: "0.3.0", catalog: [release("0.3.0")]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testOneVersionBehindShowsThatRelease() {
        let result = WhatsNewGate.releasesToPresent(
            current: "0.3.0", lastSeen: "0.2.0", catalog: [release("0.3.0"), release("0.2.0")]
        )
        XCTAssertEqual(result.map(\.version), ["0.3.0"])
    }

    func testSeveralVersionsBehindShowsAllNewerReleases() {
        let result = WhatsNewGate.releasesToPresent(
            current: "0.5.0", lastSeen: "0.2.0",
            catalog: [release("0.5.0"), release("0.4.0"), release("0.3.0"), release("0.2.0")]
        )
        XCTAssertEqual(result.map(\.version), ["0.5.0", "0.4.0", "0.3.0"])
    }

    func testCatalogEntriesNewerThanCurrentAreExcluded() {
        // Dev build running older than the newest catalog entry.
        let result = WhatsNewGate.releasesToPresent(
            current: "0.3.0", lastSeen: "0.2.0", catalog: [release("0.4.0"), release("0.3.0")]
        )
        XCTAssertEqual(result.map(\.version), ["0.3.0"])
    }

    func testVersionNotInCatalogShowsNothing() {
        let result = WhatsNewGate.releasesToPresent(
            current: "0.3.1", lastSeen: "0.3.0", catalog: [release("0.3.0")]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testNumericComparisonNotLexicographic() {
        XCTAssertTrue(WhatsNewGate.isVersion("0.10.0", newerThan: "0.9.0"))
        XCTAssertFalse(WhatsNewGate.isVersion("0.9.0", newerThan: "0.10.0"))
    }

    func testDifferentComponentCounts() {
        XCTAssertTrue(WhatsNewGate.isVersion("1.0.1", newerThan: "1.0"))
        XCTAssertFalse(WhatsNewGate.isVersion("1.0", newerThan: "1.0.0"))
    }

    func testNonNumericComponentsDoNotCrash() {
        XCTAssertFalse(WhatsNewGate.isVersion("abc", newerThan: "1.0"))
        XCTAssertTrue(WhatsNewGate.isVersion("1.0", newerThan: "abc"))
    }

    func testCatalogIsSortedNewestFirstAndNonEmpty() {
        let versions = WhatsNewCatalog.releases.map(\.version)
        XCTAssertFalse(versions.isEmpty)
        for pair in zip(versions, versions.dropFirst()) {
            XCTAssertTrue(WhatsNewGate.isVersion(pair.0, newerThan: pair.1))
        }
    }
}
