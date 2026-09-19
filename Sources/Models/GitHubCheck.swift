// ABOUTME: Normalizes GitHub check runs and legacy commit statuses for PR badges.
// ABOUTME: Unknown or missing results never imply that a PR can be merged.

import Foundation

enum GitHubCheckState: String, Equatable, Sendable {
    case passed, failed, pending, cancelled, skipped, unknown

    var titleKey: String {
        switch self {
        case .passed: "Checks passed"
        case .failed: "Checks failed"
        case .pending: "Checks pending"
        case .cancelled: "Checks cancelled"
        case .skipped: "Checks skipped"
        case .unknown: "Checks unavailable"
        }
    }

    var symbol: String {
        switch self {
        case .passed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .pending: "clock"
        case .cancelled: "nosign"
        case .skipped: "minus.circle"
        case .unknown: "questionmark.circle"
        }
    }

    init(result: String) {
        switch result.uppercased() {
        case "SUCCESS", "PASS": self = .passed
        case "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE", "FAIL": self = .failed
        case "PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "EXPECTED": self = .pending
        case "CANCELLED", "CANCEL": self = .cancelled
        case "SKIPPED", "NEUTRAL", "SKIPPING": self = .skipped
        default: self = .unknown
        }
    }
}

struct GitHubCheck: Equatable, Sendable {
    let name: String
    let state: GitHubCheckState
    let link: String
    var workflow: String = ""

    static func rollup(_ value: Any?) -> [GitHubCheck]? {
        guard let items = value as? [[String: Any]] else { return nil }
        return items.map { item in
            let isRun = item["__typename"] as? String == "CheckRun" || item["name"] != nil
            let status = item["status"] as? String ?? ""
            let result = isRun
                ? (status == "COMPLETED" ? item["conclusion"] as? String ?? "" : status)
                : item["state"] as? String ?? ""
            return GitHubCheck(
                name: item[isRun ? "name" : "context"] as? String ?? "",
                state: GitHubCheckState(result: result),
                link: item[isRun ? "detailsUrl" : "targetUrl"] as? String ?? "",
                workflow: item["workflowName"] as? String ?? ""
            )
        }
    }

    static func summary(_ checks: [GitHubCheck]?) -> GitHubCheckState {
        guard let checks, !checks.isEmpty else { return .unknown }
        for state in [GitHubCheckState.failed, .cancelled, .pending, .unknown] {
            if checks.contains(where: { $0.state == state }) { return state }
        }
        // gh's PR rollup query can stop at the first page of contexts.
        // A full page cannot establish that every check passed.
        if checks.count >= 100 { return .unknown }
        return checks.allSatisfy { $0.state == .skipped } ? .skipped : .passed
    }
}

extension GitHubPR {
    var checksIdentity: String { "\(url)|\(headOID)" }

    func checksAreStale(at date: Date) -> Bool {
        guard let fetchedAt else { return true }
        return date.timeIntervalSince(fetchedAt) > 90
    }

    static func decode(_ dict: [String: Any], fetchedAt: Date = Date()) -> GitHubPR? {
        guard let number = dict["number"] as? Int,
              let title = dict["title"] as? String,
              let state = dict["state"] as? String,
              let branch = dict["headRefName"] as? String,
              let url = dict["url"] as? String else { return nil }
        let checks = GitHubCheck.rollup(dict["statusCheckRollup"])
        let reviewDecision = dict["reviewDecision"] as? String
        let latestReviews = dict["latestReviews"] as? [[String: Any]]
        let codeRabbit = decodeCodeRabbitStatus(checks: checks, latestReviews: latestReviews)
        let hasReviewFindings = (reviewDecision == "CHANGES_REQUESTED") || codeRabbit.hasFindings

        return GitHubPR(
            number: number,
            title: title,
            state: state,
            branch: branch,
            url: url,
            checks: checks,
            headOID: dict["headRefOid"] as? String ?? "",
            isDraft: dict["isDraft"] as? Bool ?? false,
            reviewDecision: reviewDecision,
            mergeStateStatus: dict["mergeStateStatus"] as? String,
            mergeable: dict["mergeable"] as? String,
            fetchedAt: fetchedAt,
            hasReviewFindings: hasReviewFindings,
            codeRabbitStatus: codeRabbit.status
        )
    }

    static func decodeCodeRabbitStatus(
        checks: [GitHubCheck]?,
        latestReviews: [[String: Any]]?
    ) -> (status: CodeRabbitStatus, hasFindings: Bool) {
        let codeRabbitCheck = checks?.first(where: {
            $0.name.localizedCaseInsensitiveContains("coderabbit")
                || $0.workflow.localizedCaseInsensitiveContains("coderabbit")
        })
        let isReviewing = codeRabbitCheck?.state == .pending

        var findingsCount: Int? = nil
        var hasFindings = false
        var foundCodeRabbitReview = false

        if let latestReviews {
            for review in latestReviews {
                let author = review["author"] as? [String: Any]
                let login = (author?["login"] as? String) ?? ""
                let state = (review["state"] as? String) ?? ""
                let body = (review["body"] as? String) ?? ""

                if login.localizedCaseInsensitiveContains("coderabbit") {
                    foundCodeRabbitReview = true
                    if let regex = try? NSRegularExpression(pattern: #"\*\*Actionable comments posted:\s*(\d+)\*\*"#, options: .caseInsensitive),
                       let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                       let range = Range(match.range(at: 1), in: body),
                       let count = Int(body[range]) {
                        findingsCount = count
                        if count > 0 {
                            hasFindings = true
                        }
                    } else if body.contains("<!-- autofix_checkbox_start -->") || state == "CHANGES_REQUESTED" {
                        hasFindings = true
                    }
                    break
                }
            }
        }

        if hasFindings {
            return (.hasFindings(count: findingsCount), true)
        } else if isReviewing {
            return (.reviewing, false)
        } else if foundCodeRabbitReview || (codeRabbitCheck != nil && codeRabbitCheck?.state == .passed) {
            return (.clean, false)
        } else {
            return (.notConfigured, false)
        }
    }
}

