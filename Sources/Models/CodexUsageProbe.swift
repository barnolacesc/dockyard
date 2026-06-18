// ABOUTME: Fetches and parses Codex `/status` output for sidebar usage meters.
// ABOUTME: Codex reports remaining quota, which is adapted to Dockyard's used-percent UI.

import Foundation

struct CodexUsageReport: Equatable {
    struct Window: Equatable {
        var percentLeft: Int
        var resetText: String?
    }

    var model: String?
    var account: String?
    var fiveHour: Window?
    var week: Window?

    var isEmpty: Bool {
        fiveHour == nil && week == nil
    }
}

enum CodexUsageProbe {
    private static let probeTimeout: TimeInterval = 8

    static func fetch(shell: String = CommandBuilder.userShell) -> CodexUsageReport? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = [
            "-lic",
            "printf '/status\\r/quit\\r' | script -q /dev/null codex --no-alt-screen"
        ]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeout = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + probeTimeout, execute: timeout)

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> CodexUsageReport? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parseText(text)
    }

    static func parseText(_ text: String) -> CodexUsageReport? {
        let lines = stripANSI(text)
            .split(whereSeparator: \.isNewline)
            .map { normalizedLine(String($0)) }
            .filter { !$0.isEmpty }

        var report = CodexUsageReport()
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if lower.contains("model:"), report.model == nil {
                report.model = value(afterColonIn: line)
            } else if lower.contains("account:"), report.account == nil {
                report.account = value(afterColonIn: line)
            } else if lower.contains("5h limit:"),
                      let percent = percentLeft(in: line)
            {
                report.fiveHour = CodexUsageReport.Window(
                    percentLeft: percent,
                    resetText: resetText(after: index, in: lines)
                )
            } else if lower.contains("weekly limit:"),
                      let percent = percentLeft(in: line)
            {
                report.week = CodexUsageReport.Window(
                    percentLeft: percent,
                    resetText: resetText(after: index, in: lines)
                )
            }
        }

        return report.isEmpty ? nil : report
    }

    static func percentUsed(fromPercentLeft percentLeft: Int) -> Int {
        max(0, min(100, 100 - percentLeft))
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }

    private static func normalizedLine(_ line: String) -> String {
        line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n|"))
    }

    private static func value(afterColonIn line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        var value = String(line[line.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = value.lastIndex(of: "|") {
            value = String(value[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? nil : value
    }

    private static func percentLeft(in line: String) -> Int? {
        guard let range = line.range(
            of: #"\d+\s*%\s*left"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let match = String(line[range])
        guard let percentRange = match.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(match[percentRange])
    }

    private static func resetText(after index: Int, in lines: [String]) -> String? {
        let nextIndex = index + 1
        guard lines.indices.contains(nextIndex) else { return nil }
        let line = lines[nextIndex]
        guard let range = line.range(
            of: #"resets\s+([^)]+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        var text = String(line[range])
        text = text.replacingOccurrences(
            of: #"(?i)^resets\s+"#,
            with: "",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "() |").union(.whitespacesAndNewlines))
        return text.isEmpty ? nil : text
    }
}
