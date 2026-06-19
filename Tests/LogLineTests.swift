// ABOUTME: Tests unified-log level mapping and plain-text export formatting.
// ABOUTME: Keeps the logs window value model deterministic and sortable.

@testable import Dockyard
import OSLog
import XCTest

final class LogLineTests: XCTestCase {
    func testMapsSystemLogLevels() {
        XCTAssertEqual(LogLevel(from: .undefined), .debug)
        XCTAssertEqual(LogLevel(from: .debug), .debug)
        XCTAssertEqual(LogLevel(from: .info), .info)
        XCTAssertEqual(LogLevel(from: .notice), .notice)
        XCTAssertEqual(LogLevel(from: .error), .error)
        XCTAssertEqual(LogLevel(from: .fault), .fault)
    }

    func testLevelsSortBySeverity() {
        XCTAssertEqual(
            [LogLevel.fault, .debug, .error, .notice, .info].sorted(),
            [.debug, .info, .notice, .error, .fault]
        )
    }

    func testExportsDeterministicTextLine() {
        let line = LogLine(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
            date: Date(timeIntervalSince1970: 0),
            category: "network",
            level: .error,
            message: "Request failed"
        )

        XCTAssertEqual(line.exportText, "1970-01-01T00:00:00.000Z [ERROR] network: Request failed")
    }
}
