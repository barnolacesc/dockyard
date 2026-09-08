// ABOUTME: Tests deterministic normalization of untrusted GitHub issue previews.
// ABOUTME: Covers malformed metadata, URL validation, and bounded body retention.

@testable import Dockyard
import XCTest

final class GitHubIssueTaskPreviewTests: XCTestCase {
    func testParsesAndNormalizesIssueMetadata() throws {
        let preview = GitHubIssueTaskPreview.parse(jsonData: try jsonData([
            "number": 145,
            "title": "  Add\tissue\n task\u{0000}preview  ",
            "url": "  https://github.com/barnolacesc/dockyard/issues/145?notification_referrer=test#comment  ",
            "body": "  First line\r\nSecond\rThird\u{0007}\tvalue  ",
        ]))

        XCTAssertEqual(preview?.number, 145)
        XCTAssertEqual(preview?.title, "Add issue task preview")
        XCTAssertEqual(preview?.url.absoluteString, "https://github.com/barnolacesc/dockyard/issues/145")
        XCTAssertEqual(preview?.body, "First line\nSecond\nThird \tvalue")
        XCTAssertEqual(preview?.isBodyTruncated, false)
    }

    func testAllowsMissingBody() throws {
        let preview = GitHubIssueTaskPreview.parse(jsonData: try jsonData([
            "number": 7,
            "title": "Body is optional",
            "url": "https://github.com/owner/repository/issues/7",
            "body": NSNull(),
        ]))

        XCTAssertEqual(preview?.body, "")
        XCTAssertEqual(preview?.isBodyTruncated, false)
    }

    func testBoundsBodyWithoutSplittingCharacters() throws {
        let emoji = "👩‍💻"
        let retainedPrefix = String(repeating: "a", count: GitHubIssueTaskPreview.maximumBodyCharacters - 1)
        let preview = GitHubIssueTaskPreview.parse(jsonData: try jsonData([
            "number": 8,
            "title": "Bound the body",
            "url": "https://github.com/owner/repository/issues/8",
            "body": retainedPrefix + emoji + "discarded",
        ]))

        XCTAssertEqual(preview?.body.count, GitHubIssueTaskPreview.maximumBodyCharacters)
        XCTAssertTrue(preview?.body.hasSuffix(emoji) == true)
        XCTAssertEqual(preview?.isBodyTruncated, true)
    }

    func testAcceptsBodyExactlyAtLimit() throws {
        let body = String(repeating: "a", count: GitHubIssueTaskPreview.maximumBodyCharacters)
        let preview = GitHubIssueTaskPreview.parse(jsonData: try jsonData([
            "number": 9,
            "title": "Exact body limit",
            "url": "https://github.com/owner/repository/issues/9",
            "body": body,
        ]))

        XCTAssertEqual(preview?.body, body)
        XCTAssertEqual(preview?.isBodyTruncated, false)
    }

    func testRejectsMalformedOrInvalidRequiredFields() throws {
        XCTAssertNil(GitHubIssueTaskPreview.parse(jsonData: Data("not json".utf8)))
        XCTAssertNil(GitHubIssueTaskPreview.parse(jsonData: try jsonData([
            "number": 12,
            "url": "https://github.com/owner/repository/issues/12",
        ])))
        XCTAssertNil(try preview(number: 0))
        XCTAssertNil(try preview(title: " \n\t "))
        XCTAssertNil(try preview(url: "javascript:alert(1)"))
        XCTAssertNil(try preview(url: "http://github.com/owner/repository/issues/12"))
        XCTAssertNil(try preview(url: "https://user@github.com/owner/repository/issues/12"))
        XCTAssertNil(try preview(url: "https://example.com/owner/repository/issues/12"))
        XCTAssertNil(try preview(url: "https://github.com/owner/repository/issues/99"))
    }

    func testRejectsPayloadAboveHardLimit() {
        let oversizedData = Data(repeating: 0x20, count: GitHubIssueTaskPreview.maximumPayloadBytes + 1)

        XCTAssertNil(GitHubIssueTaskPreview.parse(jsonData: oversizedData))
    }

    private func preview(
        number: Int = 12,
        title: String = "Issue title",
        url: String = "https://github.com/owner/repository/issues/12"
    ) throws -> GitHubIssueTaskPreview? {
        GitHubIssueTaskPreview.parse(jsonData: try jsonData([
            "number": number,
            "title": title,
            "url": url,
            "body": "Issue body",
        ]))
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
