// ABOUTME: Tests quick-action routing and prompt metadata.
// ABOUTME: Keeps agent delegation decisions covered without invoking terminal UI.

@testable import Dockyard
import XCTest

private final class QuickActionProcessDouble: QuickActionProcess, @unchecked Sendable {
    private(set) var terminateCallCount = 0
    private var completion: (@Sendable (QuickActionProcessResult) -> Void)?

    func capture(completion: @escaping @Sendable (QuickActionProcessResult) -> Void) {
        self.completion = completion
    }

    func terminate() {
        terminateCallCount += 1
    }

    func complete(output: String, exitCode: Int32) {
        completion?(QuickActionProcessResult(output: output, exitCode: exitCode))
    }
}

@MainActor
final class QuickActionTests: XCTestCase {
    func testDelegatesToAgentOnlyForCommitAndCreatePR() {
        XCTAssertTrue(QuickAction.commit.delegatesToAgent)
        XCTAssertTrue(QuickAction.createPR.delegatesToAgent)
        XCTAssertFalse(QuickAction.push.delegatesToAgent)
        XCTAssertFalse(QuickAction.closePR.delegatesToAgent)
    }

    func testPromptOnlyExistsForDelegatedActions() {
        XCTAssertEqual(
            QuickAction.commit.prompt,
            "Stage and commit all changes in the working tree with a good commit message based on the changes. Do not push."
        )
        XCTAssertEqual(
            QuickAction.createPR.prompt,
            "Create a pull request for the current changes. Write a clear title and description based on what we've been working on."
        )
        XCTAssertNil(QuickAction.push.prompt)
        XCTAssertNil(QuickAction.closePR.prompt)
    }

    func testDelegatedActionsAreNotDisabledByMissingDirectTooling() {
        XCTAssertNil(QuickAction.commit.disabledReason(ghPath: nil))
        XCTAssertNil(QuickAction.createPR.disabledReason(ghPath: nil))
    }

    func testClosePRRequiresGhCLI() {
        XCTAssertEqual(
            QuickAction.closePR.disabledReason(ghPath: nil),
            "gh CLI is not installed."
        )
        XCTAssertNil(QuickAction.closePR.disabledReason(ghPath: "/opt/homebrew/bin/gh"))
    }

    func testCancelTerminatesRunningClosePRAndIgnoresLateCompletion() async {
        let process = QuickActionProcessDouble()
        var successCallCount = 0
        let runner = QuickActionRunner { executableURL, arguments, workingDirectoryURL, completion in
            XCTAssertEqual(executableURL.path, "/usr/local/bin/gh")
            XCTAssertEqual(arguments, ["pr", "close", "feature/test", "--comment", "Closed from Dockyard"])
            XCTAssertEqual(workingDirectoryURL.path, "/tmp/worktree")
            process.capture(completion: completion)
            return process
        }
        runner.onSuccess = { _ in successCallCount += 1 }

        runner.run(
            action: .closePR,
            ghPath: "/usr/local/bin/gh",
            workingDirectory: "/tmp/worktree",
            branchName: "feature/test"
        )
        XCTAssertEqual(runner.state, .running(.closePR))

        runner.cancel()
        XCTAssertEqual(process.terminateCallCount, 1)
        XCTAssertEqual(runner.state, .idle)

        process.complete(output: "closed after cancellation", exitCode: 0)
        await Task.yield()

        XCTAssertEqual(runner.state, .idle)
        XCTAssertEqual(runner.log.last?.output, "")
        XCTAssertNil(runner.log.last?.exitCode)
        XCTAssertEqual(successCallCount, 0)
    }

    func testClosePRCompletionPublishesOneTerminalState() async {
        let process = QuickActionProcessDouble()
        var successCallCount = 0
        let runner = QuickActionRunner { _, _, _, completion in
            process.capture(completion: completion)
            return process
        }
        runner.onSuccess = { _ in successCallCount += 1 }

        runner.run(
            action: .closePR,
            ghPath: "/usr/local/bin/gh",
            workingDirectory: "/tmp/worktree",
            branchName: "feature/test"
        )
        process.complete(output: "Pull request closed", exitCode: 0)
        await Task.yield()

        XCTAssertEqual(runner.state, .succeeded(.closePR))
        XCTAssertEqual(runner.log.last?.output, "Pull request closed")
        XCTAssertEqual(runner.log.last?.exitCode, 0)
        XCTAssertEqual(successCallCount, 1)

        process.complete(output: "duplicate callback", exitCode: 1)
        await Task.yield()

        XCTAssertEqual(runner.state, .succeeded(.closePR))
        XCTAssertEqual(runner.log.last?.output, "Pull request closed")
        XCTAssertEqual(runner.log.last?.exitCode, 0)
        XCTAssertEqual(successCallCount, 1)
    }

    func testClosePRFailurePreservesExitCode() async {
        let process = QuickActionProcessDouble()
        let runner = QuickActionRunner { _, _, _, completion in
            process.capture(completion: completion)
            return process
        }

        runner.run(
            action: .closePR,
            ghPath: "/usr/local/bin/gh",
            workingDirectory: "/tmp/worktree",
            branchName: "feature/test"
        )
        process.complete(output: "not found", exitCode: 4)
        await Task.yield()

        XCTAssertEqual(runner.state, .failed(.closePR))
        XCTAssertEqual(runner.log.last?.output, "not found")
        XCTAssertEqual(runner.log.last?.exitCode, 4)
    }
}
