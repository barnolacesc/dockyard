// ABOUTME: Tests Monaco editor resource requests stay inside the bundled resource root.
// ABOUTME: Covers valid descendants, traversal attempts, and same-prefix sibling paths.

@testable import Dockyard
import Foundation
import XCTest

@MainActor
final class MonacoResourceSchemeHandlerTests: XCTestCase {
    private let baseURL = URL(
        fileURLWithPath: "/Applications/Dockyard.app/Contents/Resources/MonacoEditor",
        isDirectory: true
    )

    func testAcceptsDirectAndNestedDescendants() {
        let directChild = baseURL.appendingPathComponent("index.html")
        let nestedChild = baseURL.appendingPathComponent("assets/editor/main.js")

        XCTAssertTrue(
            MonacoResourceSchemeHandler.isContainedResourceURL(directChild, within: baseURL)
        )
        XCTAssertTrue(
            MonacoResourceSchemeHandler.isContainedResourceURL(nestedChild, within: baseURL)
        )
    }

    func testRejectsTraversalOutsideResourceRoot() {
        let traversal = URL(
            fileURLWithPath: baseURL.path + "/../Secrets/config.json"
        )

        XCTAssertFalse(
            MonacoResourceSchemeHandler.isContainedResourceURL(traversal, within: baseURL)
        )
    }

    func testRejectsSiblingWithSharedStringPrefix() {
        let sibling = URL(
            fileURLWithPath: baseURL.path + "Backup/index.html"
        )

        XCTAssertFalse(
            MonacoResourceSchemeHandler.isContainedResourceURL(sibling, within: baseURL)
        )
    }

    func testRejectsResourceRootItself() {
        XCTAssertFalse(
            MonacoResourceSchemeHandler.isContainedResourceURL(baseURL, within: baseURL)
        )
    }
}
