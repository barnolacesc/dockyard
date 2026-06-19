// ABOUTME: Represents one unified-log entry and its severity.
// ABOUTME: Provides display metadata and deterministic plain-text export.

import Foundation
import OSLog
import SwiftUI

enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case notice
    case error
    case fault

    init(from level: OSLogEntryLog.Level) {
        switch level {
        case .undefined, .debug:
            self = .debug
        case .info:
            self = .info
        case .notice:
            self = .notice
        case .error:
            self = .error
        case .fault:
            self = .fault
        @unknown default:
            self = .debug
        }
    }

    var label: String {
        switch self {
        case .debug: NSLocalizedString("Debug", comment: "Log level")
        case .info: NSLocalizedString("Info", comment: "Log level")
        case .notice: NSLocalizedString("Notice", comment: "Log level")
        case .error: NSLocalizedString("Error", comment: "Log level")
        case .fault: NSLocalizedString("Fault", comment: "Log level")
        }
    }

    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: .primary
        case .notice: .blue
        case .error: .orange
        case .fault: .red
        }
    }
}

extension LogLevel: Comparable {
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        guard let lhsIndex = allCases.firstIndex(of: lhs),
              let rhsIndex = allCases.firstIndex(of: rhs)
        else { return false }
        return lhsIndex < rhsIndex
    }
}

struct LogLine: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let category: String
    let level: LogLevel
    let message: String

    init(
        id: UUID = UUID(),
        date: Date,
        category: String,
        level: LogLevel,
        message: String
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.level = level
        self.message = message
    }

    var exportText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(formatter.string(from: date)) [\(level.rawValue.uppercased())] \(category): \(message)"
    }
}
