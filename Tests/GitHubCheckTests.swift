// ABOUTME: Tests mixed CI providers, conservative summaries, and PR head freshness.
// ABOUTME: Protects against displaying successful CI for missing or outdated results.

@testable import Dockyard
import XCTest

final class GitHubCheckTests: XCTestCase {
    func testMixedCheckRunsAndLegacyStatuses() throws {
        let checks = try XCTUnwrap(GitHubCheck.rollup([
            ["__typename": "CheckRun", "name": "build", "status": "COMPLETED", "conclusion": "SUCCESS", "detailsUrl": "https://example.com/build"],
            ["__typename": "StatusContext", "context": "external", "state": "PENDING", "targetUrl": "https://example.com/external"],
        ]))
        XCTAssertEqual(checks.map(\.state), [.passed, .pending])
        XCTAssertEqual(checks[1].name, "external")
        XCTAssertEqual(checks[1].link, "https://example.com/external")
        XCTAssertEqual(GitHubCheck.summary(checks), .pending)
    }

    func testFailureWinsOverRunningChecks() {
        let checks = [check(.pending), check(.failed), check(.passed)]
        XCTAssertEqual(GitHubCheck.summary(checks), .failed)
    }

    func testMissingMalformedAndUnknownChecksNeverPass() {
        XCTAssertNil(GitHubCheck.rollup(nil))
        XCTAssertNil(GitHubCheck.rollup("bad response"))
        XCTAssertEqual(GitHubCheck.rollup([])?.count, 0)
        XCTAssertEqual(GitHubCheck.summary(nil), .unknown)
        XCTAssertEqual(GitHubCheck.summary([]), .unknown)
        XCTAssertEqual(GitHubCheck.summary([check(.passed), check(.unknown)]), .unknown)
        XCTAssertEqual(GitHubCheckState(result: "NEW_SERVER_STATE"), .unknown)
        XCTAssertEqual(GitHubCheck.summary(GitHubCheck.rollup([["__typename": "SomethingNew"]])), .unknown)
    }

    func testCancelledSkippedAndActionRequired() {
        XCTAssertEqual(GitHubCheckState(result: "CANCELLED"), .cancelled)
        XCTAssertEqual(GitHubCheckState(result: "NEUTRAL"), .skipped)
        XCTAssertEqual(GitHubCheckState(result: "ACTION_REQUIRED"), .failed)
        XCTAssertEqual(GitHubCheckState(result: "TIMED_OUT"), .failed)
        XCTAssertEqual(GitHubCheck.summary([check(.skipped)]), .skipped)
        XCTAssertEqual(GitHubCheck.summary([check(.passed), check(.skipped)]), .passed)
        XCTAssertEqual(GitHubCheck.summary([check(.passed), check(.cancelled)]), .cancelled)
    }

    func testQueuedRunDoesNotUseOldConclusion() {
        let checks = GitHubCheck.rollup([["name": "build", "status": "QUEUED", "conclusion": "SUCCESS"]])
        XCTAssertEqual(checks?.first?.state, .pending)
    }

    func testFullPageDoesNotClaimAllChecksPassed() {
        XCTAssertEqual(GitHubCheck.summary(Array(repeating: check(.passed), count: 100)), .unknown)
    }

    func testNewHeadReplacesChecksAndChangesDetailIdentity() throws {
        var payload: [String: Any] = ["number": 12, "title": "Feature", "state": "OPEN",
                                      "headRefName": "feat/test", "url": "https://github.com/a/b/pull/12",
                                      "headRefOid": "old", "isDraft": true, "reviewDecision": "REVIEW_REQUIRED",
                                      "statusCheckRollup": [["name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"]]]
        let date = Date(timeIntervalSince1970: 1000)
        let old = try XCTUnwrap(GitHubPR.decode(payload, fetchedAt: date))
        XCTAssertTrue(old.isDraft)
        XCTAssertEqual(old.reviewDecision, "REVIEW_REQUIRED")
        XCTAssertFalse(old.checksAreStale(at: date.addingTimeInterval(30)))
        XCTAssertTrue(old.checksAreStale(at: date.addingTimeInterval(91)))
        payload["headRefOid"] = "new"
        payload["statusCheckRollup"] = []
        let new = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertNotEqual(old.checksIdentity, new.checksIdentity)
        XCTAssertEqual(new.checks, [])
        XCTAssertEqual(GitHubCheck.summary(new.checks), .unknown)
    }

    func testRequiredCheckResponseMustBeStructured() throws {
        let json = Data(#"[{"name":"test","bucket":"fail","link":"https://example.com/log","workflow":"CI"}]"#.utf8)
        let checks = try XCTUnwrap(GitHubOperations.decodeRequiredChecks(json))
        XCTAssertEqual(checks.first?.state, .failed)
        XCTAssertEqual(checks.first?.workflow, "CI")
        XCTAssertNil(GitHubOperations.decodeRequiredChecks(Data("authentication failed".utf8)))
        XCTAssertNil(GitHubOperations.decodeRequiredChecks(Data(#"[{"message":"API failure"}]"#.utf8)))
        XCTAssertEqual(GitHubOperations.decodeRequiredChecks(Data("[]".utf8)), [])
    }

    func testConflictDetection() throws {
        var payload: [String: Any] = [
            "number": 1, "title": "PR", "state": "OPEN", "headRefName": "feat", "url": "https://example.com/1",
            "mergeStateStatus": "DIRTY", "mergeable": "MERGEABLE"
        ]
        let pr1 = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertTrue(pr1.hasConflicts)

        payload["mergeStateStatus"] = "BLOCKED"
        payload["mergeable"] = "CONFLICTING"
        let pr2 = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertTrue(pr2.hasConflicts)

        payload["mergeStateStatus"] = "CLEAN"
        payload["mergeable"] = "MERGEABLE"
        let pr3 = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertFalse(pr3.hasConflicts)
    }

    func testCodeRabbitReviewDecoding() throws {
        // 1. Pending check -> reviewing
        var payload: [String: Any] = [
            "number": 2, "title": "PR", "state": "OPEN", "headRefName": "feat", "url": "https://example.com/2",
            "statusCheckRollup": [
                ["name": "CodeRabbit", "status": "IN_PROGRESS", "state": "PENDING"]
            ]
        ]
        let pr1 = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertEqual(pr1.codeRabbitStatus, .reviewing)
        XCTAssertFalse(pr1.hasReviewFindings)

        // 2. Actionable comments posted -> hasFindings
        payload["statusCheckRollup"] = [
            ["name": "CodeRabbit", "status": "COMPLETED", "conclusion": "SUCCESS"]
        ]
        payload["latestReviews"] = [
            [
                "author": ["login": "coderabbitai[bot]"],
                "state": "COMMENTED",
                "body": "**Actionable comments posted: 4**\n\n---\n<!-- autofix_checkbox_start -->"
            ]
        ]
        let pr2 = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertEqual(pr2.codeRabbitStatus, .hasFindings(count: 4))
        XCTAssertTrue(pr2.hasReviewFindings)

        // 3. 0 actionable comments posted -> clean
        payload["latestReviews"] = [
            [
                "author": ["login": "coderabbitai"],
                "state": "COMMENTED",
                "body": "**Actionable comments posted: 0**\n\nNo issues found."
            ]
        ]
        let pr3 = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertEqual(pr3.codeRabbitStatus, .clean)
        XCTAssertFalse(pr3.hasReviewFindings)
    }

    func testReviewStatusDecoding() throws {
        var payload: [String: Any] = [
            "number": 3, "title": "PR", "state": "OPEN", "headRefName": "feat", "url": "https://example.com/3",
            "isDraft": true
        ]
        let draftPR = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertEqual(draftPR.reviewStatus, .draft)

        payload["isDraft"] = false
        payload["reviewDecision"] = "APPROVED"
        let approvedPR = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertEqual(approvedPR.reviewStatus, .approved)

        payload["reviewDecision"] = "CHANGES_REQUESTED"
        let changesPR = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertEqual(changesPR.reviewStatus, .changesRequested)
        XCTAssertTrue(changesPR.hasReviewFindings)

        payload["reviewDecision"] = "REVIEW_REQUIRED"
        let reviewPR = try XCTUnwrap(GitHubPR.decode(payload))
        XCTAssertEqual(reviewPR.reviewStatus, .awaitingReview)
    }

    private func check(_ state: GitHubCheckState) -> GitHubCheck {
        GitHubCheck(name: "test", state: state, link: "")
    }
}
