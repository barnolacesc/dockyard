// ABOUTME: Executes prompt launch wrappers to verify retry and respawn behavior.
// ABOUTME: Checks receipt-driven consumption without requiring a live Ghostty surface.

@testable import Dockyard
import XCTest

final class AgentInitialPromptTests: XCTestCase {
    private func run(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard prompt's \(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testSuccessfulSessionDoesNotReplayPromptWhenOriginalCommandIsRespawned() throws {
        let directory = try temporaryDirectory()
        let receipt = AgentInitialPrompt.receiptURL(for: UUID(), directory: directory)
        let log = directory.appendingPathComponent("launches")
        let prompt = "Fix 'auth'\n$PATH; `touch injected`"
        let quotedLog = CommandBuilder.shellQuote(log.path)
        let wrapper = AgentInitialPrompt.wrap(
            command: "printf '%s\\n' \(CommandBuilder.shellQuote(prompt)) >> \(quotedLog)",
            continuation: "printf '%s\\n' resumed >> \(quotedLog)",
            receiptURL: receipt
        )

        XCTAssertEqual(try run(wrapper), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
        // tmux retains and re-executes this exact original command.
        XCTAssertEqual(try run(wrapper), 0)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), prompt + "\nresumed\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("injected").path))
    }

    func testFailedLaunchKeepsPromptForRetryThenSuccessfulExitConsumesIt() throws {
        let directory = try temporaryDirectory()
        let receipt = AgentInitialPrompt.receiptURL(for: UUID(), directory: directory)
        let ready = directory.appendingPathComponent("ready")
        let log = directory.appendingPathComponent("launches")
        let quotedLog = CommandBuilder.shellQuote(log.path)
        let command = "printf '%s\\n' issue >> \(quotedLog); [ -f \(CommandBuilder.shellQuote(ready.path)) ]"
        let wrapper = AgentInitialPrompt.wrap(
            command: command,
            continuation: "printf '%s\\n' resumed >> \(quotedLog)",
            receiptURL: receipt
        )

        XCTAssertEqual(try run(wrapper), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
        try Data().write(to: ready)
        XCTAssertEqual(try run(wrapper), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
        XCTAssertEqual(try run(wrapper), 0)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "issue\nissue\nresumed\n")
    }

    func testReceiptIsNotWrittenWhileInteractiveCommandIsStillRunning() throws {
        let directory = try temporaryDirectory()
        let receipt = AgentInitialPrompt.receiptURL(for: UUID(), directory: directory)
        let observed = directory.appendingPathComponent("observed")
        let wrapper = AgentInitialPrompt.wrap(
            command: "[ ! -f \(CommandBuilder.shellQuote(receipt.path)) ] && touch \(CommandBuilder.shellQuote(observed.path))",
            continuation: "exit 99",
            receiptURL: receipt
        )
        XCTAssertEqual(try run(wrapper), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: observed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
    }

    func testEveryProviderRetainsFailedPromptAndOmitsItAfterSuccess() throws {
        for cli in CodingCLI.allCases {
            let directory = try temporaryDirectory()
            let executable = directory.appendingPathComponent("fake-agent")
            let ready = directory.appendingPathComponent("ready")
            let log = directory.appendingPathComponent("arguments")
            let script = """
            #!/bin/sh
            printf '<%s>' "$@" >> \(CommandBuilder.shellQuote(log.path))
            printf '\\n' >> \(CommandBuilder.shellQuote(log.path))
            [ -f \(CommandBuilder.shellQuote(ready.path)) ] || exit 42
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let workstreamID = UUID()
            let receipt = AgentInitialPrompt.receiptURL(for: workstreamID)
            defer { try? FileManager.default.removeItem(at: receipt) }
            let prompt = "Implement issue #42: 'auth'\n$PATH & `cmd`"
            let launch = CodingCLICommandBuilder.buildAgentCommand(
                cli: cli,
                cliPath: CommandBuilder.shellQuote(executable.path),
                workingDirectory: directory.path,
                projectName: "test",
                workstreamName: "issue-42",
                workstreamID: workstreamID,
                tmuxPath: nil,
                useTmux: false,
                bypassPermissions: false,
                allowOutsideWorktree: true,
                autoRenameBranch: false,
                envVars: [:],
                supportsSessionName: false,
                initialPrompt: prompt
            )
            XCTAssertEqual(try run(launch.finalCommand), 42, cli.rawValue)
            XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path), cli.rawValue)
            XCTAssertTrue(try String(contentsOf: log, encoding: .utf8).contains("<\(prompt)>"), cli.rawValue)
            try Data().write(to: ready)
            XCTAssertEqual(try run(launch.finalCommand), 0, cli.rawValue)
            XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path), cli.rawValue)
            try Data().write(to: log)
            XCTAssertEqual(try run(launch.finalCommand), 0, cli.rawValue)
            XCTAssertFalse(try String(contentsOf: log, encoding: .utf8).contains(prompt), cli.rawValue)
        }
    }

    @MainActor
    func testCacheOnlyConsumesPromptOnceReceiptExists() async throws {
        let directory = try temporaryDirectory()
        let workstreamID = UUID()
        let receipt = AgentInitialPrompt.receiptURL(for: workstreamID, directory: directory)
        let consumed = expectation(description: "Prompt consumed once after successful exit")
        consumed.assertForOverFulfill = true
        let observer = NotificationCenter.default.addObserver(
            forName: .initialAgentPromptConsumed, object: nil, queue: nil
        ) { notification in
            if notification.object as? UUID == workstreamID { consumed.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let cache = TerminalSurfaceCache()
        cache.trackInitialPrompt(for: workstreamID, receiptURL: receipt)
        cache.checkPendingInitialPrompts()
        try FileManager.default.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: receipt)
        cache.checkPendingInitialPrompts()
        cache.trackInitialPrompt(for: workstreamID, receiptURL: receipt)
        cache.checkPendingInitialPrompts()
        await fulfillment(of: [consumed], timeout: 1)
        cache.removeWorkstreamSurfaces(for: workstreamID)
    }

    @MainActor
    func testCacheRecoversReceiptWrittenWhileAppWasClosed() async throws {
        let directory = try temporaryDirectory()
        let workstreamID = UUID()
        let receipt = AgentInitialPrompt.receiptURL(for: workstreamID, directory: directory)
        try FileManager.default.createDirectory(at: receipt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: receipt)
        let consumed = expectation(description: "Previously completed session is recovered")
        let observer = NotificationCenter.default.addObserver(
            forName: .initialAgentPromptConsumed, object: nil, queue: nil
        ) { notification in
            if notification.object as? UUID == workstreamID { consumed.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let cache = TerminalSurfaceCache()
        cache.trackInitialPrompt(for: workstreamID, receiptURL: receipt)
        cache.checkPendingInitialPrompts()
        await fulfillment(of: [consumed], timeout: 1)
        cache.removeWorkstreamSurfaces(for: workstreamID)
    }
}
