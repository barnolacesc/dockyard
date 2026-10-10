// ABOUTME: Exercises explicit Codex ownership, failed resumes, and one-shot prompts.

@testable import Dockyard
import XCTest

final class CodexSessionTests: XCTestCase {
    func testCleanupStopsOwnedDescendantsInSeparateGroupsAndPreservesUnrelatedProcess() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let childFile = temp.appendingPathComponent("child-pid")
        let owned = Process()
        owned.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        owned.arguments = ["-c", "import subprocess,time,pathlib; p=subprocess.Popen(['sleep','60'],start_new_session=True); pathlib.Path(\(String(reflecting: childFile.path))).write_text(str(p.pid)); time.sleep(60)"]
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["60"]
        try owned.run()
        try unrelated.run()
        defer {
            if owned.isRunning { owned.terminate() }
            if unrelated.isRunning { unrelated.terminate() }
        }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: childFile.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let childPID = try XCTUnwrap(Int32(String(contentsOf: childFile)))
        let id = UUID()
        try CodexSession.registerOwnedProcess(pid: owned.processIdentifier, for: id, directory: temp)
        CodexSession.terminateOwnedProcesses(for: id, directory: temp, beforeTermination: {
            // Simulate tmux closing its pane: the detached child must still
            // be cleaned up from the tree captured before its parent exits.
            owned.terminate()
        })
        while owned.isRunning || RunStateStore.isProcessRunning(pid: childPID), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(owned.isRunning)
        XCTAssertFalse(RunStateStore.isProcessRunning(pid: childPID))
        XCTAssertTrue(unrelated.isRunning)
    }

    func testStaleProcessBirthTimeDoesNotSignalReusedPID() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let stale = CodexOwnedProcess(pid: process.processIdentifier, startedAt: .distantPast)
        try FilePersistence.writeAtomically(JSONEncoder().encode(stale), to: CodexSession.processURL(for: workstreamID, directory: directory))
        CodexSession.terminateOwnedProcesses(for: workstreamID, directory: directory)
        XCTAssertTrue(process.isRunning)
    }

    private var directory: URL!
    private var worktree: URL!
    private var workstreamID: UUID!
    private var threadID: UUID!
    private var helper: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        worktree = directory.appendingPathComponent("worktree with spaces")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        workstreamID = UUID()
        threadID = UUID()
        helper = try XCTUnwrap(AgentHooks.bundledHelperPath)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func payload(event: String = "SessionStart", id: UUID? = nil, cwd: String? = nil, prompt: String? = nil) throws -> Data {
        var input = ["hook_event_name": event, "session_id": (id ?? threadID).uuidString, "cwd": cwd ?? worktree.path]
        input["prompt"] = prompt
        return try JSONSerialization.data(withJSONObject: input)
    }

    private func record(_ id: UUID? = nil) throws {
        try CodexSession.recordHook(payload(id: id), for: workstreamID, workingDirectory: worktree.path, environment: [:], directory: directory)
    }

    func testHookRecordsActualThreadAndRejectsSiblingDirectory() throws {
        try record()
        XCTAssertNotEqual(threadID, workstreamID)
        XCTAssertEqual(CodexSession.load(for: workstreamID, workingDirectory: worktree.path, directory: directory)?.threadID, threadID)
        XCTAssertThrowsError(try CodexSession.recordHook(payload(cwd: directory.path), for: workstreamID, workingDirectory: worktree.path, directory: directory))
        XCTAssertNil(CodexSession.load(for: workstreamID, workingDirectory: directory.path, directory: directory))
    }

    func testSeedReceiptRequiresMatchingPromptAndThread() throws {
        let prompt = "Seed \"this\" task\nonly once"
        let env = ["DOCKYARD_CODEX_INITIAL_PROMPT": prompt]
        let receipt = AgentInitialPrompt.receiptURL(for: workstreamID, directory: directory)
        try CodexSession.recordHook(payload(event: "UserPromptSubmit", prompt: "different"), for: workstreamID, workingDirectory: worktree.path, environment: env, directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.path))
        try CodexSession.recordHook(payload(event: "UserPromptSubmit", prompt: prompt), for: workstreamID, workingDirectory: worktree.path, environment: env, directory: directory)
        XCTAssertEqual(try String(contentsOf: receipt), threadID.uuidString)
    }

    func testQuotedMultilineSeedIsAcknowledgedOnceAcrossReopen() throws {
        let prompt = "Task 'alpha' with \"quotes\" and $literal\nNext line"
        XCTAssertEqual(try launch(prompt: prompt).0, 0)
        let receipt = AgentInitialPrompt.receiptURL(for: workstreamID, directory: directory)
        XCTAssertEqual(try String(contentsOf: receipt), threadID.uuidString)
        XCTAssertEqual(try launch(prompt: prompt).1, ["resume \(threadID.uuidString.lowercased())"])
    }

    /// The fake CLI executes the bundled hook helper just like Codex. It can
    /// reject an explicit resume before startup or fail after startup.
    private func launch(
        resumeFails: Bool = false,
        resumeExit: Int32? = nil,
        freshFails: Bool = false,
        startedExit: Int = 0,
        prompt: String? = nil
    ) throws -> (Int32, [String]) {
        let cli = directory.appendingPathComponent("fake-codex")
        let log = directory.appendingPathComponent("invocations")
        try? FileManager.default.removeItem(at: log)
        let quote: (String) -> String = { CommandBuilder.shellQuote($0) }
        let args = "\(quote(helper)) --workstream-id \(workstreamID.uuidString) --working-directory \(quote(worktree.path)) --codex-config-directory \(quote(directory.path)) --codex-record"
        let start = try quote(String(decoding: payload(), as: UTF8.self))
        let submit = try quote(String(decoding: payload(event: "UserPromptSubmit", prompt: prompt), as: UTF8.self))
        let resumeExitCode = resumeExit ?? (resumeFails ? 1 : nil)
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> \(quote(log.path))
        if [ "$1" = resume ]; then
          \(resumeExitCode.map { "exit \($0)" } ?? ":")
        else
          \(freshFails ? "exit 1" : ":")
        fi
        printf '%s' \(start) | \(args) >/dev/null || exit $?
        if [ -n "${DOCKYARD_CODEX_INITIAL_PROMPT:-}" ]; then
          printf '%s' \(submit) | \(args) >/dev/null || exit $?
        fi
        exit \(startedExit)
        """
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let command = CodexSession.wrap(fresh: quote(cli.path), resume: "\(quote(cli.path)) resume \"$dockyard_codex_thread\"", helperPath: helper, workstreamID: workstreamID, workingDirectory: worktree.path, initialPrompt: prompt, directory: directory, shell: "/bin/sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        let lines = (try? String(contentsOf: log).split(separator: "\n").map(String.init)) ?? []
        return (process.terminationStatus, lines)
    }

    func testFreshAndLegacyIgnoreSiblingAssociation() throws {
        let siblingID = UUID()
        try CodexSession.recordHook(payload(id: UUID()), for: siblingID, workingDirectory: worktree.path, directory: directory)
        let result = try launch()
        XCTAssertEqual(result.0, 0)
        XCTAssertTrue(result.1.isEmpty) // Fresh invocation has no resume arguments.
        XCTAssertEqual(CodexSession.load(for: workstreamID, workingDirectory: worktree.path, directory: directory)?.threadID, threadID)
    }

    func testReopenUsesSavedThreadEvenAfterSiblingUpdated() throws {
        try record()
        try CodexSession.recordHook(payload(id: UUID()), for: UUID(), workingDirectory: worktree.path, directory: directory)
        let result = try launch()
        XCTAssertEqual(result.1, ["resume \(threadID.uuidString.lowercased())"])
    }

    func testMissingThreadClearsOnlyOwnAssociationAndStartsFresh() throws {
        try record(UUID())
        let siblingID = UUID()
        try CodexSession.recordHook(payload(), for: siblingID, workingDirectory: worktree.path, directory: directory)
        let result = try launch(resumeFails: true, prompt: "my seed")
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1.count, 2)
        XCTAssertEqual(result.1.last, "my seed")
        XCTAssertEqual(CodexSession.load(for: workstreamID, workingDirectory: worktree.path, directory: directory)?.threadID, threadID)
        XCTAssertNotNil(CodexSession.load(for: siblingID, workingDirectory: worktree.path, directory: directory))
    }

    func testGenericStartupFailureDoesNotClearValidThreadAssociation() throws {
        try record()
        let result = try launch(resumeFails: true, freshFails: true, prompt: "my seed")
        XCTAssertEqual(result.0, 1)
        XCTAssertEqual(result.1.count, 2)
        XCTAssertEqual(CodexSession.load(for: workstreamID, workingDirectory: worktree.path, directory: directory)?.threadID, threadID)
    }

    func testSignalInterruptionDuringResumeDoesNotRunFreshOrClearAssociation() throws {
        try record()
        let result = try launch(resumeExit: 130)
        XCTAssertEqual(result.0, 130)
        XCTAssertEqual(result.1, ["resume \(threadID.uuidString.lowercased())"])
        XCTAssertEqual(CodexSession.load(for: workstreamID, workingDirectory: worktree.path, directory: directory)?.threadID, threadID)
    }

    func testResolveMismatchDoesNotDeleteValidAssociation() throws {
        try record()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = [
            "--workstream-id", workstreamID.uuidString,
            "--working-directory", "/nonexistent/mismatched/directory",
            "--codex-config-directory", directory.path,
            "--codex-resolve",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(output.isEmpty)
        XCTAssertEqual(CodexSession.load(for: workstreamID, workingDirectory: worktree.path, directory: directory)?.threadID, threadID)
    }

    func testPurgeRemovesSessionAndProcessRecords() throws {
        try record()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        try CodexSession.registerOwnedProcess(pid: process.processIdentifier, for: workstreamID, directory: directory)

        XCTAssertNotNil(CodexSession.load(for: workstreamID, workingDirectory: worktree.path, directory: directory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CodexSession.processURL(for: workstreamID, directory: directory).path))

        CodexSession.remove(for: workstreamID, directory: directory)

        XCTAssertNil(CodexSession.load(for: workstreamID, workingDirectory: worktree.path, directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: CodexSession.processURL(for: workstreamID, directory: directory).path))
    }

    func testFailureAfterSessionStartDoesNotStartAnotherThreadOrReplaySeed() throws {
        try record()
        let first = try launch(startedExit: 1, prompt: "intended seed")
        XCTAssertEqual(first.0, 1)
        XCTAssertEqual(first.1, ["resume \(threadID.uuidString.lowercased()) intended seed"])
        let second = try launch(prompt: "intended seed")
        XCTAssertEqual(second.1, ["resume \(threadID.uuidString.lowercased())"])
    }

    func testMalformedAssociationStartsFreshAndMissingDirectoryDoesNotLaunch() throws {
        try FilePersistence.writeAtomically(Data("invalid".utf8), to: CodexSession.fileURL(for: workstreamID, directory: directory))
        XCTAssertEqual(try launch(prompt: "fresh seed").1, ["fresh seed"])
        try FileManager.default.removeItem(at: worktree)
        XCTAssertEqual(try launch().0, 1)
    }
}
