// ABOUTME: Fetches REAL Claude usage by running `claude -p /usage` (a client-side command —
// ABOUTME: no model call, no token/quota cost) and parsing the session/week percentages.

import Foundation

/// Real usage figures parsed from Claude Code's `/usage` output. Unlike the local-transcript
/// estimate, these are the authoritative account numbers (all models, web + CLI).
struct ClaudeUsageReport: Equatable {
    struct Window: Equatable {
        var percentUsed: Int
        var resetText: String?
    }

    var session: Window?
    var week: Window?

    var isEmpty: Bool { session == nil && week == nil }
}

enum ClaudeUsageProbe {
    /// Run `claude -p /usage --output-format json` via the login shell and parse the result.
    /// `/usage` is intercepted client-side, so this makes no model request (cost/quota = 0).
    /// Returns nil if claude isn't installed, the call fails, or nothing parseable comes back.
    /// Must be called off the main actor (it blocks on a subprocess).
    static func fetch(shell: String = CommandBuilder.userShell) -> ClaudeUsageReport? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", "claude -p '/usage' --output-format json"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }

    /// Parse the `--output-format json` envelope, then the human-readable `result` text.
    static func parse(_ data: Data) -> ClaudeUsageReport? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? String else { return nil }
        return parseText(result)
    }

    /// Parse the `/usage` body, e.g.:
    /// `Current session: 63% used · resets Jun 14 at 3pm (Europe/Madrid)`
    /// `Current week (all models): 43% used · resets Jun 17 at 9am (Europe/Madrid)`
    static func parseText(_ text: String) -> ClaudeUsageReport? {
        var report = ClaudeUsageReport()
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine)
            let lower = line.lowercased()
            guard lower.contains("% used"), let percent = firstPercent(in: line) else { continue }
            let window = ClaudeUsageReport.Window(percentUsed: percent, resetText: resetText(in: line))
            if lower.contains("session") {
                report.session = window
            } else if lower.contains("week") {
                report.week = window
            }
        }
        return report.isEmpty ? nil : report
    }

    /// First integer immediately followed by `%`.
    private static func firstPercent(in line: String) -> Int? {
        guard let range = line.range(of: #"\d+%"#, options: .regularExpression) else { return nil }
        return Int(line[range].dropLast())
    }

    /// Text after "resets ", trimmed and stripped of a trailing timezone parenthetical.
    private static func resetText(in line: String) -> String? {
        guard let r = line.range(of: "resets ") else { return nil }
        var rest = String(line[r.upperBound...])
        if let paren = rest.firstIndex(of: "(") {
            rest = String(rest[..<paren])
        }
        let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
