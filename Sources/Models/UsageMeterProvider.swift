// ABOUTME: Shared provider model and pure helpers for sidebar usage meters.
// ABOUTME: Maps Coding Agent choices to available meter implementations.

import Foundation

enum UsageMeterProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:
            return CodingCLI.claude.displayName
        case .codex:
            return CodingCLI.codex.displayName
        }
    }

    static func preferred(for cli: CodingCLI) -> UsageMeterProvider? {
        switch cli {
        case .claude:
            return .claude
        case .codex:
            return .codex
        case .opencode, .gemini:
            return nil
        }
    }
}

struct UsageMeterWindow: Equatable {
    var percentUsed: Int?
    var tokens: Int?
    var resetText: String?
}

struct UsageMeterSnapshot: Equatable {
    var provider: UsageMeterProvider
    var displayName: String
    var current: UsageMeterWindow?
    var weekly: UsageMeterWindow?
}

func cycledUsageMeterProvider(
    current: UsageMeterProvider,
    available: [UsageMeterProvider],
    direction: Int
) -> UsageMeterProvider {
    guard !available.isEmpty,
          let index = available.firstIndex(of: current)
    else {
        return available.first ?? current
    }
    let next = (index + direction + available.count) % available.count
    return available[next]
}

func resolvedUsageMeterProvider(
    current: UsageMeterProvider,
    preferred: UsageMeterProvider?,
    previousPreferred: UsageMeterProvider?,
    available: [UsageMeterProvider]
) -> UsageMeterProvider {
    if let preferred,
       preferred != previousPreferred,
       available.contains(preferred)
    {
        return preferred
    }
    if available.contains(current) {
        return current
    }
    if let preferred, available.contains(preferred) {
        return preferred
    }
    return available.first ?? current
}
