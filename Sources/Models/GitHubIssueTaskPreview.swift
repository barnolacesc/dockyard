// ABOUTME: Normalizes GitHub issue metadata into a bounded read-only task preview.
// ABOUTME: Treats issue JSON as untrusted input without launching commands or agents.

import Foundation

struct GitHubIssueTaskPreview: Equatable, Sendable {
    static let maximumPayloadBytes = 1_048_576
    static let maximumBodyCharacters = 16_384

    let number: Int
    let title: String
    let url: URL
    let body: String
    let isBodyTruncated: Bool

    static func parse(jsonData: Data) -> GitHubIssueTaskPreview? {
        guard jsonData.count <= maximumPayloadBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: jsonData),
              payload.number > 0
        else { return nil }

        let title = normalizeTitle(payload.title)
        guard !title.isEmpty,
              let url = canonicalIssueURL(payload.url, issueNumber: payload.number)
        else { return nil }

        let normalizedBody = normalizeBody(payload.body ?? "")
        let retainedBody = normalizedBody.prefix(maximumBodyCharacters + 1)
        let isBodyTruncated = retainedBody.count > maximumBodyCharacters

        return GitHubIssueTaskPreview(
            number: payload.number,
            title: title,
            url: url,
            body: String(retainedBody.prefix(maximumBodyCharacters)),
            isBodyTruncated: isBodyTruncated
        )
    }

    private static func normalizeTitle(_ title: String) -> String {
        title
            .unicodeScalars
            .map { scalar in
                if CharacterSet.whitespacesAndNewlines.contains(scalar)
                    || isDisallowedControl(scalar)
                {
                    return " "
                }
                return String(scalar)
            }
            .joined()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func normalizeBody(_ body: String) -> String {
        let normalizedLineEndings = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return normalizedLineEndings.unicodeScalars.map { scalar in
            if scalar == "\n" || scalar == "\t" {
                return String(scalar)
            }
            if isDisallowedControl(scalar) {
                return " "
            }
            return String(scalar)
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDisallowedControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F ... 0x9F).contains(scalar.value)
    }

    private static func canonicalIssueURL(_ rawURL: String, issueNumber: Int) -> URL? {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedURL),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com",
              components.port == nil,
              components.user == nil,
              components.password == nil
        else { return nil }

        let pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard pathComponents.count == 4,
              pathComponents[2] == "issues",
              Int(pathComponents[3]) == issueNumber,
              !pathComponents[0].isEmpty,
              !pathComponents[1].isEmpty
        else { return nil }

        var canonicalComponents = URLComponents()
        canonicalComponents.scheme = "https"
        canonicalComponents.host = "github.com"
        canonicalComponents.path = "/" + pathComponents.joined(separator: "/")
        return canonicalComponents.url
    }

    private struct Payload: Decodable {
        let number: Int
        let title: String
        let url: String
        let body: String?
    }
}
