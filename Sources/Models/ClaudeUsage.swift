// ABOUTME: Parses local Claude Code transcript files to estimate token usage over the
// ABOUTME: rolling 5-hour block and 7-day window, for the sidebar usage meter.

import Foundation

/// Subscription plan tier. Used only to render an *approximate* "% remaining" — Anthropic
/// does not publish exact subscription token limits, so the per-window budgets below are
/// rough community estimates. They are intentionally easy to tune in one place. Default is
/// `.none`, in which case the meter shows raw consumption with no percentage.
enum ClaudePlanTier: String, CaseIterable, Identifiable {
    case none
    case pro
    case max5
    case max20

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return NSLocalizedString("Not set", comment: "")
        case .pro: return "Pro"
        case .max5: return "Max 5×"
        case .max20: return "Max 20×"
        }
    }

    /// Approximate "work token" budget for a single 5-hour block. Rough estimate, not an
    /// official figure. nil means "don't show a percentage".
    var fiveHourTokenBudget: Int? {
        switch self {
        case .none: return nil
        case .pro: return 200_000
        case .max5: return 1_000_000
        case .max20: return 4_000_000
        }
    }

    /// Approximate "work token" budget for the rolling 7-day window. Same caveat as
    /// `fiveHourTokenBudget`: a rough estimate, easy to tune here.
    var weeklyTokenBudget: Int? {
        switch self {
        case .none: return nil
        case .pro: return 1_500_000
        case .max5: return 7_500_000
        case .max20: return 30_000_000
        }
    }
}

/// One usage window: tokens consumed plus when (if known) the window resets.
struct ClaudeUsageWindow: Equatable {
    var tokens: Int = 0
    var resetAt: Date?
}

/// A point-in-time view of recent Claude usage.
struct ClaudeUsageSnapshot: Equatable {
    var fiveHour = ClaudeUsageWindow()
    var sevenDay = ClaudeUsageWindow()
    /// True once at least one usage record has been parsed (so the UI can hide the meter
    /// entirely when there's no Claude activity to report).
    var hasData = false
}

/// Pure parsing/aggregation of Claude Code transcript token usage. Stateless and testable.
enum ClaudeUsageParser {
    static let fiveHours: TimeInterval = 5 * 3600
    static let sevenDays: TimeInterval = 7 * 24 * 3600

    struct Entry: Equatable {
        let time: Date
        let tokens: Int
    }

    static func defaultProjectsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Parse transcripts and aggregate into a snapshot. `projectsDir` defaults to
    /// `~/.claude/projects`. Bounded by file mtime so old transcripts are skipped.
    static func compute(now: Date = Date(), projectsDir: URL? = nil) -> ClaudeUsageSnapshot {
        let dir = projectsDir ?? defaultProjectsDirectory()
        // Include a little slack before the 7-day window so block boundaries near the edge
        // are computed correctly.
        let horizon = now.addingTimeInterval(-(sevenDays + fiveHours))
        let entries = parseEntries(in: dir, since: horizon)
        return aggregate(entries: entries, now: now)
    }

    /// Read every `*.jsonl` under `dir` (recursively) modified at/after `since`, extracting
    /// (timestamp, tokens) for each assistant line that carries a `usage` object.
    static func parseEntries(in dir: URL, since: Date) -> [Entry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [Entry] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let mtime = values.contentModificationDate, mtime < since {
                continue
            }
            entries.append(contentsOf: parseFile(at: url, since: since))
        }
        return entries
    }

    private static func parseFile(at url: URL, since: Date) -> [Entry] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var entries: [Entry] = []
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            // Cheap pre-filter: only assistant lines carry a usage object.
            guard line.contains("\"usage\"") else { continue }
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(TranscriptLine.self, from: data),
                  let usage = record.message?.usage,
                  let timeString = record.timestamp,
                  let time = parseTimestamp(timeString),
                  time >= since
            else { continue }
            entries.append(Entry(time: time, tokens: usage.workTokens))
        }
        return entries
    }

    /// Aggregate entries into the 5-hour block and 7-day rolling windows.
    static func aggregate(entries: [Entry], now: Date) -> ClaudeUsageSnapshot {
        guard !entries.isEmpty else { return ClaudeUsageSnapshot() }
        let sorted = entries.sorted { $0.time < $1.time }

        // 7-day rolling total.
        let weekStart = now.addingTimeInterval(-sevenDays)
        let weekTokens = sorted.filter { $0.time >= weekStart }.reduce(0) { $0 + $1.tokens }

        // 5-hour blocks: a block runs for 5h from its first message; a gap of >= 5h between
        // consecutive messages also starts a new block (mirrors how usage windows reset).
        var blockStart: Date?
        var lastTime: Date?
        var blockTokens = 0
        for entry in sorted {
            if let start = blockStart, let last = lastTime,
               entry.time.timeIntervalSince(start) < fiveHours,
               entry.time.timeIntervalSince(last) < fiveHours {
                blockTokens += entry.tokens
            } else {
                blockStart = entry.time
                blockTokens = entry.tokens
            }
            lastTime = entry.time
        }

        var snapshot = ClaudeUsageSnapshot()
        snapshot.hasData = true
        snapshot.sevenDay = ClaudeUsageWindow(tokens: weekTokens, resetAt: nil)
        if let start = blockStart, now.timeIntervalSince(start) < fiveHours {
            snapshot.fiveHour = ClaudeUsageWindow(tokens: blockTokens, resetAt: start.addingTimeInterval(fiveHours))
        }
        return snapshot
    }

    // MARK: - Decoding

    private static let decoder = JSONDecoder()

    private struct TranscriptLine: Decodable {
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let usage: Usage?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }

            /// Tokens that represent real work for limit purposes. Both cache reads *and*
            /// cache creation are excluded: they replay/establish context rather than
            /// reflecting new conversational work, and cache-creation volume is so large and
            /// bursty that it makes the percentage estimate meaningless.
            var workTokens: Int {
                (inputTokens ?? 0) + (outputTokens ?? 0)
            }
        }
    }

    // ISO8601DateFormatter is thread-safe for read-only parsing, but isn't marked Sendable;
    // these are only ever read (never reconfigured), so the unchecked annotation is sound.
    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseTimestamp(_ string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }
}
