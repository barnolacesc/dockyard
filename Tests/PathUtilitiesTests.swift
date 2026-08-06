// ABOUTME: Tests component-aware abbreviation of paths beneath the current user's home directory.
// ABOUTME: Prevents prefix siblings from being displayed as though they were inside the home directory.

@testable import Dockyard
import XCTest

final class PathUtilitiesTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func testHomeDirectoryAbbreviatesToTilde() {
        XCTAssertEqual(home.abbreviatedPath, "~")
    }

    func testHomeDescendantsAbbreviateWithTildePrefix() {
        XCTAssertEqual("\(home)/Projects/Dockyard".abbreviatedPath, "~/Projects/Dockyard")
    }

    func testHomePrefixSiblingRemainsUnchanged() {
        let sibling = "\(home)-old/Projects/Dockyard"

        XCTAssertEqual(sibling.abbreviatedPath, sibling)
    }

    func testRelativeAndUnrelatedPathsRemainUnchanged() {
        XCTAssertEqual("Projects/Dockyard".abbreviatedPath, "Projects/Dockyard")
        XCTAssertEqual("/var/tmp/dockyard".abbreviatedPath, "/var/tmp/dockyard")
    }
}
