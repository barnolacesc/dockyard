// ABOUTME: Tests for resolving absolute paths to app-launched command line tools.
// ABOUTME: Guards against debug and release builds using different command lookup behavior.

@testable import Dockyard
import XCTest

private final class LoginShellProcessDouble: LoginShellProcess, @unchecked Sendable {
    var result: LoginShellProcessResult
    var waitResults: [Bool]
    private(set) var runCallCount = 0
    private(set) var waitTimeouts: [TimeInterval] = []
    private(set) var terminateCallCount = 0
    private(set) var forceTerminateCallCount = 0

    init(
        output: String = "",
        terminationStatus: Int32 = 0,
        outputExceededLimit: Bool = false,
        waitResults: [Bool] = [true]
    ) {
        result = LoginShellProcessResult(
            output: Data(output.utf8),
            terminationStatus: terminationStatus,
            outputExceededLimit: outputExceededLimit
        )
        self.waitResults = waitResults
    }

    func run() throws {
        runCallCount += 1
    }

    func waitForExit(timeout: TimeInterval) -> Bool {
        waitTimeouts.append(timeout)
        return waitResults.isEmpty ? false : waitResults.removeFirst()
    }

    func terminate() {
        terminateCallCount += 1
    }

    func forceTerminate() {
        forceTerminateCallCount += 1
    }
}

private final class LoginShellProcessProvider: @unchecked Sendable {
    let process: LoginShellProcessDouble
    private(set) var factoryCallCount = 0

    init(process: LoginShellProcessDouble) {
        self.process = process
    }

    func makeProcess(
        executableURL: URL,
        arguments: [String],
        maximumOutputBytes: Int
    ) -> any LoginShellProcess {
        factoryCallCount += 1
        return process
    }
}

final class CommandLineToolsTests: XCTestCase {
    func testLoginShellPathUsesBoundedProcessAndParsesPath() {
        let process = LoginShellProcessDouble(output: " /opt/homebrew/bin:/usr/bin \n")
        let cache = CommandLineTools.ShellPathCache { executableURL, arguments, maximumOutputBytes in
            XCTAssertEqual(executableURL.path, "/bin/zsh")
            XCTAssertEqual(arguments, ["-lic", "printenv PATH"])
            XCTAssertEqual(maximumOutputBytes, CommandLineTools.maximumLoginShellOutputBytes)
            return process
        }

        XCTAssertEqual(cache.resolve(shell: "/bin/zsh"), "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(process.runCallCount, 1)
        XCTAssertEqual(process.waitTimeouts, [CommandLineTools.loginShellTimeout])
        XCTAssertEqual(process.terminateCallCount, 0)
        XCTAssertEqual(process.forceTerminateCallCount, 0)
    }

    func testLoginShellPathTerminatesThenForceTerminatesAfterTimeout() {
        let process = LoginShellProcessDouble(waitResults: [false, false, true])
        let cache = CommandLineTools.ShellPathCache { _, _, _ in process }

        XCTAssertNil(cache.resolve(shell: "/bin/zsh"))
        XCTAssertEqual(
            process.waitTimeouts,
            [
                CommandLineTools.loginShellTimeout,
                CommandLineTools.loginShellTerminationGrace,
                CommandLineTools.loginShellTerminationGrace,
            ]
        )
        XCTAssertEqual(process.terminateCallCount, 1)
        XCTAssertEqual(process.forceTerminateCallCount, 1)
    }

    func testLoginShellPathDoesNotForceTerminateAfterGracefulExit() {
        let process = LoginShellProcessDouble(waitResults: [false, true])
        let cache = CommandLineTools.ShellPathCache { _, _, _ in process }

        XCTAssertNil(cache.resolve(shell: "/bin/zsh"))
        XCTAssertEqual(
            process.waitTimeouts,
            [CommandLineTools.loginShellTimeout, CommandLineTools.loginShellTerminationGrace]
        )
        XCTAssertEqual(process.terminateCallCount, 1)
        XCTAssertEqual(process.forceTerminateCallCount, 0)
    }

    func testLoginShellPathRejectsOversizedOutput() {
        let process = LoginShellProcessDouble(
            output: "/partial/path",
            outputExceededLimit: true
        )
        let cache = CommandLineTools.ShellPathCache { _, _, _ in process }

        XCTAssertNil(cache.resolve(shell: "/bin/zsh"))
    }

    func testLoginShellPathCachesFailure() {
        let process = LoginShellProcessDouble(terminationStatus: 1)
        let provider = LoginShellProcessProvider(process: process)
        let cache = CommandLineTools.ShellPathCache { executableURL, arguments, maximumOutputBytes in
            provider.makeProcess(
                executableURL: executableURL,
                arguments: arguments,
                maximumOutputBytes: maximumOutputBytes
            )
        }

        XCTAssertNil(cache.resolve(shell: "/bin/zsh"))
        XCTAssertNil(cache.resolve(shell: "/bin/zsh"))
        XCTAssertEqual(provider.factoryCallCount, 1)
        XCTAssertEqual(process.runCallCount, 1)
    }

    func testPrefersLoginShellPath() {
        // The login shell PATH should take priority over known locations
        // so we find the same binary the user's terminal would.
        var knownLocationChecked = false
        let resolved = CommandLineTools.path(
            for: "claude",
            environment: ["SHELL": "/bin/zsh"],
            isExecutable: { path in
                if path == "/opt/homebrew/bin/claude" { knownLocationChecked = true }
                return path == "/Users/me/.nvm/versions/node/v22/bin/claude"
            },
            resolveFromPath: { _, _ in nil },
            resolveFromShellPath: { shell in
                XCTAssertEqual(shell, "/bin/zsh")
                return "/Users/me/.nvm/versions/node/v22/bin:/opt/homebrew/bin:/usr/bin"
            }
        )

        XCTAssertEqual(resolved, "/Users/me/.nvm/versions/node/v22/bin/claude")
        XCTAssertFalse(knownLocationChecked, "Known locations should not be checked when shell PATH matches")
    }

    func testFallsBackToProcessPathWhenShellPathMisses() {
        let resolved = CommandLineTools.path(
            for: "mytool",
            environment: ["PATH": "/custom/bin", "SHELL": "/bin/zsh"],
            isExecutable: { $0 == "/custom/bin/mytool" },
            resolveFromPath: { name, env in
                let rawPath = env["PATH"] ?? ""
                for dir in rawPath.split(separator: ":") {
                    let candidate = "\(dir)/\(name)"
                    if candidate == "/custom/bin/mytool" { return candidate }
                }
                return nil
            },
            resolveFromShellPath: { _ in
                // Shell PATH doesn't contain the tool
                "/usr/bin:/bin"
            }
        )

        XCTAssertEqual(resolved, "/custom/bin/mytool")
    }

    func testFallsBackToKnownLocationsAsLastResort() {
        let resolved = CommandLineTools.path(
            for: "git",
            environment: ["PATH": "", "SHELL": "/bin/zsh"],
            isExecutable: { $0 == "/opt/homebrew/bin/git" },
            resolveFromPath: { _, _ in nil },
            resolveFromShellPath: { _ in
                // Shell PATH doesn't contain the tool either
                "/usr/bin:/bin"
            }
        )

        XCTAssertEqual(resolved, "/opt/homebrew/bin/git")
    }

    func testReturnsNilWhenNothingFound() {
        let resolved = CommandLineTools.path(
            for: "nonexistent",
            environment: ["PATH": "", "SHELL": "/bin/zsh"],
            isExecutable: { _ in false },
            resolveFromPath: { _, _ in nil },
            resolveFromShellPath: { _ in "/usr/bin:/bin" }
        )

        XCTAssertNil(resolved)
    }

    func testFallsBackToNixSystemLocation() {
        let resolved = CommandLineTools.path(
            for: "tmux",
            environment: ["PATH": "", "SHELL": "/bin/zsh"],
            isExecutable: { $0 == "/run/current-system/sw/bin/tmux" },
            resolveFromPath: { _, _ in nil },
            resolveFromShellPath: { _ in "/usr/bin:/bin" }
        )

        XCTAssertEqual(resolved, "/run/current-system/sw/bin/tmux")
    }

    func testFallsBackToNixProfileLocation() {
        let nixProfilePath = "\(NSHomeDirectory())/.nix-profile/bin/gh"
        let resolved = CommandLineTools.path(
            for: "gh",
            environment: ["PATH": "", "SHELL": "/bin/zsh"],
            isExecutable: { $0 == nixProfilePath },
            resolveFromPath: { _, _ in nil },
            resolveFromShellPath: { _ in "/usr/bin:/bin" }
        )

        XCTAssertEqual(resolved, nixProfilePath)
    }

    func testSkipsShellPathWhenShellNotSet() {
        // No SHELL in environment, should skip shell PATH and fall through
        let resolved = CommandLineTools.path(
            for: "git",
            environment: ["PATH": ""],
            isExecutable: { $0 == "/usr/local/bin/git" },
            resolveFromPath: { _, _ in nil },
            resolveFromShellPath: { _ in
                XCTFail("Shell PATH should not be queried when SHELL is not set")
                return nil
            }
        )

        XCTAssertEqual(resolved, "/usr/local/bin/git")
    }

    func testRecoversFromInvalidShellPathUsingSystemFallback() {
        let resolved = CommandLineTools.path(
            for: "codex",
            environment: ["PATH": "", "SHELL": "/usr/bin/zsh"],
            isExecutable: { $0 == "/Users/me/.npm-global/bin/codex" },
            resolveFromPath: { _, _ in nil },
            resolveFromShellPath: { shell in
                XCTAssertNotEqual(shell, "/usr/bin/zsh")
                return "/Users/me/.npm-global/bin:/usr/bin:/bin"
            }
        )

        XCTAssertEqual(resolved, "/Users/me/.npm-global/bin/codex")
    }
}
