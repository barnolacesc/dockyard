// ABOUTME: Tests quick-action routing and prompt metadata.
// ABOUTME: Keeps agent delegation decisions covered without invoking terminal UI.

@testable import Dockyard
import XCTest

final class QuickActionTests: XCTestCase {
    func testDelegatesToAgentOnlyForCommitAndCreatePR() {
        XCTAssertTrue(QuickAction.commit.delegatesToAgent)
        XCTAssertTrue(QuickAction.createPR.delegatesToAgent)
        XCTAssertFalse(QuickAction.push.delegatesToAgent)
        XCTAssertFalse(QuickAction.closePR.delegatesToAgent)
    }

    func testPromptOnlyExistsForDelegatedActions() {
        XCTAssertEqual(
            QuickAction.commit.prompt,
            "Stage and commit all changes in the working tree with a good commit message based on the changes. Do not push."
        )
        XCTAssertEqual(
            QuickAction.createPR.prompt,
            "Create a pull request for the current changes. Write a clear title and description based on what we've been working on."
        )
        XCTAssertNil(QuickAction.push.prompt)
        XCTAssertNil(QuickAction.closePR.prompt)
    }

    func testDelegatedActionsAreNotDisabledByMissingDirectTooling() {
        XCTAssertNil(QuickAction.commit.disabledReason(ghPath: nil))
        XCTAssertNil(QuickAction.createPR.disabledReason(ghPath: nil))
    }

    func testClosePRRequiresGhCLI() {
        XCTAssertEqual(
            QuickAction.closePR.disabledReason(ghPath: nil),
            "gh CLI is not installed."
        )
        XCTAssertNil(QuickAction.closePR.disabledReason(ghPath: "/opt/homebrew/bin/gh"))
    }
}
