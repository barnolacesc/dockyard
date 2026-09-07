// ABOUTME: Tests for LaunchLogger per-workstream debug log file writing.
// ABOUTME: Validates serialization, opt-in gating, bounded retention, permissions, and cleanup.

@testable import Dockyard
import XCTest

final class LaunchLoggerTests: XCTestCase {
    private var testLogsDir: URL!
    private let testWorkstreamID = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!

    override func setUp() {
        super.setUp()
        testLogsDir = LaunchLogger.logsDirectoryURL
        // Ensure clean state
        try? FileManager.default.removeItem(at: testLogsDir)
        // Enable detailed logging for tests
        UserDefaults.standard.set(true, forKey: "dockyard.detailedLogging")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testLogsDir)
        UserDefaults.standard.removeObject(forKey: "dockyard.detailedLogging")
        super.tearDown()
    }

    // MARK: - Log entry encoding

    func testLogEntryRoundTrips() throws {
        let entry = LaunchLogEntry(
            workstreamID: testWorkstreamID,
            event: "agent-start",
            finalCommand: "/bin/zsh -lic 'claude --resume abc'",
            intermediateCommands: ["claude --resume abc", "tmux new-session -A -s test claude --resume abc"],
            environmentVariables: ["DY_PROJECT": "myproject"],
            workingDirectory: "/tmp/test",
            toolPaths: LaunchLogEntry.ToolPaths(agentCLI: "claude", claude: "/usr/local/bin/claude", codex: nil, tmux: "/usr/bin/tmux", ffRun: nil),
            settings: LaunchLogEntry.Settings(tmuxMode: true, bypassPermissions: false, agentTeams: false, autoRenameBranch: true, allowOutsideWorktree: false),
            shell: "/bin/zsh"
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LaunchLogEntry.self, from: data)

        XCTAssertEqual(decoded.workstreamID, testWorkstreamID)
        XCTAssertEqual(decoded.event, "agent-start")
        XCTAssertEqual(decoded.finalCommand, entry.finalCommand)
        XCTAssertEqual(decoded.intermediateCommands, entry.intermediateCommands)
        XCTAssertEqual(decoded.environmentVariables, entry.environmentVariables)
        XCTAssertEqual(decoded.workingDirectory, "/tmp/test")
        XCTAssertEqual(decoded.toolPaths.agentCLI, "claude")
        XCTAssertEqual(decoded.toolPaths.claude, "/usr/local/bin/claude")
        XCTAssertNil(decoded.toolPaths.codex)
        XCTAssertEqual(decoded.toolPaths.tmux, "/usr/bin/tmux")
        XCTAssertNil(decoded.toolPaths.ffRun)
        XCTAssertTrue(decoded.settings.tmuxMode)
        XCTAssertFalse(decoded.settings.bypassPermissions)
        XCTAssertTrue(decoded.settings.autoRenameBranch)
        XCTAssertEqual(decoded.shell, "/bin/zsh")
    }

    func testLogEntryTimestampIsISO8601() throws {
        let entry = makeEntry(event: "agent-start")
        let data = try JSONEncoder().encode(entry)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let timestamp = try XCTUnwrap(json["timestamp"] as? String)

        // ISO 8601 format: contains date separator and time separator
        XCTAssertTrue(timestamp.contains("T"), "Timestamp should be ISO 8601 format")
        XCTAssertTrue(timestamp.contains("Z") || timestamp.contains("+") || timestamp.contains("-"),
                      "Timestamp should have timezone indicator")
    }

    // MARK: - Logging gated on setting

    func testLogWritesFileWhenEnabled() {
        let entry = makeEntry(event: "agent-start")
        LaunchLogger.log(entry)

        let logFile = LaunchLogger.logFileURL(for: testWorkstreamID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path), "Log file should exist when detailed logging is enabled")
    }

    func testLogCreatesPrivateDirectoryAndFile() throws {
        LaunchLogger.log(makeEntry(event: "agent-start"))

        XCTAssertEqual(try permissions(of: LaunchLogger.logsDirectoryURL), 0o700)
        XCTAssertEqual(try permissions(of: LaunchLogger.logFileURL(for: testWorkstreamID)), 0o600)
    }

    func testLogRepairsOverlyPermissiveDirectoryAndExistingFile() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: testLogsDir, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: testLogsDir.path)

        let logFile = LaunchLogger.logFileURL(for: testWorkstreamID)
        try Data("existing entry\n".utf8).write(to: logFile)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: logFile.path)

        LaunchLogger.log(makeEntry(event: "agent-start"))

        XCTAssertEqual(try permissions(of: testLogsDir), 0o700)
        XCTAssertEqual(try permissions(of: logFile), 0o600)
        let contents = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("existing entry\n"), "Existing log contents should be preserved")
        XCTAssertTrue(contents.contains("\"event\":\"agent-start\""), "New entry should be appended")
    }

    func testLogSkipsWhenDisabled() {
        UserDefaults.standard.set(false, forKey: "dockyard.detailedLogging")

        let entry = makeEntry(event: "agent-start")
        LaunchLogger.log(entry)

        let logFile = LaunchLogger.logFileURL(for: testWorkstreamID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logFile.path), "Log file should not exist when detailed logging is disabled")
    }

    // MARK: - Append behavior

    func testLogAppendsMultipleEntries() throws {
        let entry1 = makeEntry(event: "agent-start")
        let entry2 = makeEntry(event: "run-start")
        let entry3 = makeEntry(event: "setup-start")

        LaunchLogger.log(entry1)
        LaunchLogger.log(entry2)
        LaunchLogger.log(entry3)

        let logFile = LaunchLogger.logFileURL(for: testWorkstreamID)
        let contents = try String(contentsOf: logFile, encoding: .utf8)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)

        XCTAssertEqual(lines.count, 3, "Should have 3 JSON lines")

        // Each line should be valid JSON with the correct event type
        let decoder = JSONDecoder()
        for (i, line) in lines.enumerated() {
            let data = Data(line.utf8)
            let decoded = try decoder.decode(LaunchLogEntry.self, from: data)
            let expectedEvent = ["agent-start", "run-start", "setup-start"][i]
            XCTAssertEqual(decoded.event, expectedEvent)
        }
    }

    func testLogCanReachMaximumSizeWithoutDiscardingCompleteEntries() throws {
        let entry = makeEntry(event: "boundary-entry")
        let encodedEntry = try encodedLine(for: entry)
        let existingLine = jsonLine(
            marker: "boundary-existing",
            byteCount: LaunchLogger.maximumLogFileSize - encodedEntry.count
        )
        XCTAssertEqual(existingLine.count + encodedEntry.count, LaunchLogger.maximumLogFileSize)

        try seedLog(with: existingLine)
        LaunchLogger.log(entry)

        let contents = try Data(contentsOf: LaunchLogger.logFileURL(for: testWorkstreamID))
        XCTAssertEqual(contents.count, LaunchLogger.maximumLogFileSize)
        XCTAssertTrue(contents.starts(with: existingLine))
        XCTAssertTrue(contents.suffix(encodedEntry.count).elementsEqual(encodedEntry))
    }

    func testLogTrimsOldestCompleteEntriesAtMaximumSize() throws {
        let oldestLine = jsonLine(marker: "discard-oldest", byteCount: 900_000)
        let recentLine = jsonLine(marker: "preserve-recent", byteCount: 160_000)
        try seedLog(with: oldestLine + recentLine)

        let entry = makeEntry(event: "newest-entry")
        LaunchLogger.log(entry)

        let contents = try Data(contentsOf: LaunchLogger.logFileURL(for: testWorkstreamID))
        let lines = completeLines(in: contents)
        XCTAssertLessThanOrEqual(contents.count, LaunchLogger.maximumLogFileSize)
        XCTAssertEqual(lines.count, 2)
        XCTAssertNotNil(lines[0].range(of: Data("preserve-recent".utf8)))
        XCTAssertNotNil(lines[1].range(of: Data("\"event\":\"newest-entry\"".utf8)))
        XCTAssertNil(contents.range(of: Data("discard-oldest".utf8)))
    }

    func testLogCompactsOversizedExistingFileFromBoundedTail() throws {
        let oversizedOldLine = jsonLine(
            marker: "discard-oversized-old",
            byteCount: LaunchLogger.maximumLogFileSize * 2
        )
        let recentLine = jsonLine(marker: "preserve-oversized-recent", byteCount: 4_096)
        try seedLog(with: oversizedOldLine + recentLine)

        LaunchLogger.log(makeEntry(event: "after-oversized-existing"))

        let contents = try Data(contentsOf: LaunchLogger.logFileURL(for: testWorkstreamID))
        let lines = completeLines(in: contents)
        XCTAssertLessThanOrEqual(contents.count, LaunchLogger.maximumLogFileSize)
        XCTAssertEqual(lines.count, 2)
        XCTAssertNotNil(lines[0].range(of: Data("preserve-oversized-recent".utf8)))
        XCTAssertNotNil(lines[1].range(of: Data("\"event\":\"after-oversized-existing\"".utf8)))
        XCTAssertNil(contents.range(of: Data("discard-oversized-old".utf8)))
    }

    func testLogDoesNotWritePartialOversizedEntry() throws {
        let existingLine = jsonLine(marker: "existing-remains", byteCount: 256)
        try seedLog(with: existingLine)
        let oversizedEntry = makeEntry(
            event: "oversized-entry",
            finalCommand: String(repeating: "x", count: LaunchLogger.maximumLogFileSize)
        )

        LaunchLogger.log(oversizedEntry)

        let contents = try Data(contentsOf: LaunchLogger.logFileURL(for: testWorkstreamID))
        XCTAssertEqual(contents, existingLine)
    }

    func testCompactionKeepsPrivateFilePermissions() throws {
        let oldestLine = jsonLine(marker: "discard-permissions", byteCount: 900_000)
        let recentLine = jsonLine(marker: "preserve-permissions", byteCount: 160_000)
        try seedLog(with: oldestLine + recentLine, permissions: 0o644)

        LaunchLogger.log(makeEntry(event: "permissions-entry"))

        XCTAssertEqual(try permissions(of: LaunchLogger.logsDirectoryURL), 0o700)
        XCTAssertEqual(try permissions(of: LaunchLogger.logFileURL(for: testWorkstreamID)), 0o600)
    }

    // MARK: - Separate files per workstream

    func testSeparateFilesPerWorkstream() throws {
        let otherID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let entry1 = makeEntry(event: "agent-start")
        let entry2 = LaunchLogEntry(
            workstreamID: otherID,
            event: "run-start",
            finalCommand: "npm start",
            intermediateCommands: [],
            environmentVariables: [:],
            workingDirectory: "/tmp",
            toolPaths: LaunchLogEntry.ToolPaths(agentCLI: nil, claude: nil, codex: nil, tmux: nil, ffRun: nil),
            settings: LaunchLogEntry.Settings(tmuxMode: false, bypassPermissions: false, agentTeams: false, autoRenameBranch: false, allowOutsideWorktree: false),
            shell: "/bin/zsh"
        )

        LaunchLogger.log(entry1)
        LaunchLogger.log(entry2)

        XCTAssertTrue(FileManager.default.fileExists(atPath: LaunchLogger.logFileURL(for: testWorkstreamID).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LaunchLogger.logFileURL(for: otherID).path))

        // Clean up the other file
        try? FileManager.default.removeItem(at: LaunchLogger.logFileURL(for: otherID))
    }

    // MARK: - Cleanup

    func testRemoveLogDeletesFile() {
        let entry = makeEntry(event: "agent-start")
        LaunchLogger.log(entry)

        let logFile = LaunchLogger.logFileURL(for: testWorkstreamID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))

        LaunchLogger.removeLog(for: testWorkstreamID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logFile.path), "Log file should be deleted after removeLog")
    }

    func testRemoveLogNoopsForMissingFile() {
        // Should not throw or crash
        LaunchLogger.removeLog(for: testWorkstreamID)
    }

    // MARK: - Directory

    func testLogsDirectoryIsUnderCacheDirectory() {
        let logsDir = LaunchLogger.logsDirectoryURL
        let cacheDir = AppConstants.cacheDirectory
        XCTAssertTrue(logsDir.path.hasPrefix(cacheDir.path), "Logs directory should be under cache directory")
        XCTAssertTrue(logsDir.path.hasSuffix("/logs"), "Logs directory should end with /logs")
    }

    // MARK: - Helpers

    private func makeEntry(
        event: String,
        finalCommand: String = "/bin/zsh -lic 'claude --resume abc'"
    ) -> LaunchLogEntry {
        LaunchLogEntry(
            workstreamID: testWorkstreamID,
            event: event,
            finalCommand: finalCommand,
            intermediateCommands: ["claude --resume abc"],
            environmentVariables: ["DY_PROJECT": "test"],
            workingDirectory: "/tmp/test",
            toolPaths: LaunchLogEntry.ToolPaths(agentCLI: "claude", claude: "/usr/local/bin/claude", codex: nil, tmux: nil, ffRun: nil),
            settings: LaunchLogEntry.Settings(tmuxMode: false, bypassPermissions: false, agentTeams: false, autoRenameBranch: false, allowOutsideWorktree: false),
            shell: "/bin/zsh"
        )
    }

    private func encodedLine(for entry: LaunchLogEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(entry)
        data.append(0x0A)
        return data
    }

    private func jsonLine(marker: String, byteCount: Int) -> Data {
        let prefix = Data("{\"marker\":\"\(marker)\",\"padding\":\"".utf8)
        let suffix = Data("\"}\n".utf8)
        precondition(byteCount >= prefix.count + suffix.count)
        return prefix + Data(repeating: 0x61, count: byteCount - prefix.count - suffix.count) + suffix
    }

    private func seedLog(with data: Data, permissions: Int = 0o600) throws {
        try FileManager.default.createDirectory(at: testLogsDir, withIntermediateDirectories: true)
        let fileURL = LaunchLogger.logFileURL(for: testWorkstreamID)
        try data.write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: fileURL.path)
    }

    private func completeLines(in data: Data) -> [Data] {
        data.split(separator: 0x0A, omittingEmptySubsequences: true).map(Data.init)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}
