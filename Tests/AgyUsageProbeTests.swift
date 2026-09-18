// ABOUTME: Tests parsing of Antigravity CLI `/usage` JSON and text output.
// ABOUTME: Verifies 5-hour and weekly windows map to Dockyard's usage meter rows.

@testable import Dockyard
import Foundation
import XCTest

private final class AgyUsageProbeProcessDouble: AgyUsageProbeProcess, @unchecked Sendable {
    private var outputHandler: (@Sendable (Data) -> Void)?
    private(set) var terminateCallCount = 0

    func capture(outputHandler: @escaping @Sendable (Data) -> Void) {
        self.outputHandler = outputHandler
    }

    func emitOutput(_ data: Data) {
        outputHandler?(data)
    }

    func terminate() {
        terminateCallCount += 1
    }
}

final class AgyUsageProbeTests: XCTestCase {
    private let sampleJSON = Data("""
    {
      "status": "SUCCESS",
      "response": "Gemini Models\\tWeekly Limit Remaining\\t95%\\t2026-09-25T19:17:02Z\\nGemini Models\\tFive Hour Limit Remaining\\t74%\\t2026-09-19T00:17:02Z\\n",
      "command": {
        "name": "usage",
        "data": {
          "groups": [
            {
              "name": "Gemini Models",
              "buckets": [
                {
                  "id": "gemini-weekly",
                  "name": "Weekly Limit Remaining",
                  "window": "weekly",
                  "remaining_fraction": 0.9506844878196716,
                  "reset_time": "2026-09-25T19:17:02Z"
                },
                {
                  "id": "gemini-5h",
                  "name": "Five Hour Limit Remaining",
                  "window": "5h",
                  "remaining_fraction": 0.7421268224716187,
                  "reset_time": "2026-09-19T00:17:02Z"
                }
              ]
            },
            {
              "name": "Claude and GPT models",
              "buckets": [
                {
                  "id": "3p-weekly",
                  "name": "Weekly Limit Remaining",
                  "window": "weekly",
                  "remaining_fraction": 1.0,
                  "reset_time": "2026-09-25T19:41:28Z"
                },
                {
                  "id": "3p-5h",
                  "name": "Five Hour Limit Remaining",
                  "window": "5h",
                  "remaining_fraction": 1.0,
                  "reset_time": "2026-09-19T00:41:28Z"
                }
              ]
            }
          ]
        }
      }
    }
    """.utf8)

    func testParsesJSONFormatWithWindowsAndResetTimes() {
        let report = AgyUsageProbe.parse(sampleJSON)
        XCTAssertNotNil(report)

        let formatter = ISO8601DateFormatter()
        let expectedWeeklyReset = formatter.date(from: "2026-09-25T19:17:02Z")
        let expectedFiveHourReset = formatter.date(from: "2026-09-19T00:17:02Z")

        XCTAssertEqual(report?.fiveHour?.usedPercent, 26)
        XCTAssertEqual(report?.fiveHour?.remainingPercent, 74)
        XCTAssertEqual(report?.fiveHour?.resetsAt, expectedFiveHourReset)

        XCTAssertEqual(report?.week?.usedPercent, 5)
        XCTAssertEqual(report?.week?.remainingPercent, 95)
        XCTAssertEqual(report?.week?.resetsAt, expectedWeeklyReset)
    }

    func testParsesTextFormatFallback() {
        let text = """
        Gemini Models\tWeekly Limit Remaining\t90%\t2026-09-25T19:17:02Z
        Gemini Models\tFive Hour Limit Remaining\t65%\t2026-09-19T00:17:02Z
        """
        let report = AgyUsageProbe.parse(Data(text.utf8))
        XCTAssertNotNil(report)

        let formatter = ISO8601DateFormatter()
        let expectedWeeklyReset = formatter.date(from: "2026-09-25T19:17:02Z")
        let expectedFiveHourReset = formatter.date(from: "2026-09-19T00:17:02Z")

        XCTAssertEqual(report?.fiveHour?.usedPercent, 35)
        XCTAssertEqual(report?.fiveHour?.remainingPercent, 65)
        XCTAssertEqual(report?.fiveHour?.resetsAt, expectedFiveHourReset)

        XCTAssertEqual(report?.week?.usedPercent, 10)
        XCTAssertEqual(report?.week?.remainingPercent, 90)
        XCTAssertEqual(report?.week?.resetsAt, expectedWeeklyReset)
    }

    func testReturnsNilForInvalidOrEmptyOutput() {
        XCTAssertNil(AgyUsageProbe.parse(Data("{}".utf8)))
        XCTAssertNil(AgyUsageProbe.parse(Data("random command output".utf8)))
        XCTAssertNil(AgyUsageProbe.parse(Data()))
    }

    func testFetchWithMockProcessParsesChunkedOutput() {
        let process = AgyUsageProbeProcessDouble()

        let sample = sampleJSON
        let report = AgyUsageProbe.fetch(
            shell: "/bin/zsh",
            timeout: 1,
            processFactory: { executableURL, arguments, workingDirectoryURL, outputHandler, completion in
                XCTAssertEqual(executableURL.path, "/bin/zsh")
                XCTAssertEqual(arguments, ["-lic", "agy -p '/usage' --output-format json"])
                XCTAssertEqual(workingDirectoryURL, FileManager.default.homeDirectoryForCurrentUser)

                process.capture(outputHandler: outputHandler)
                DispatchQueue.global().async {
                    outputHandler(sample.prefix(50))
                    outputHandler(sample.dropFirst(50))
                    completion(0)
                }
                return process
            }
        )

        XCTAssertNotNil(report)
        XCTAssertEqual(report?.fiveHour?.usedPercent, 26)
        XCTAssertEqual(report?.week?.usedPercent, 5)
    }

    func testFetchReturnsNilOnNonZeroExit() {
        let process = AgyUsageProbeProcessDouble()

        let report = AgyUsageProbe.fetch(
            shell: "/bin/zsh",
            timeout: 1,
            processFactory: { _, _, _, outputHandler, completion in
                process.capture(outputHandler: outputHandler)
                DispatchQueue.global().async {
                    outputHandler(Data("error: unauthorized".utf8))
                    completion(1)
                }
                return process
            }
        )

        XCTAssertNil(report)
    }
}
