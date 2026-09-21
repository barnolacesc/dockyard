// ABOUTME: Tests AgentHooks settings.json generation and per-CLI capability matrix.

@testable import Dockyard
import XCTest

final class AgentHooksTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: AgentHooks.settingsDirectoryURL)
        try? FileManager.default.removeItem(at: AgentHooks.openCodeSettingsDirectoryURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: AgentHooks.settingsDirectoryURL)
        try? FileManager.default.removeItem(at: AgentHooks.openCodeSettingsDirectoryURL)
        super.tearDown()
    }

    func testHookInvocationReturnsNilForOpenCode() throws {
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"

        XCTAssertNil(try AgentHooks.hookInvocation(for: .opencode, workstreamID: UUID(), helperPath: helperPath))
    }

    func testHookInvocationForAgyWithoutWorkingDirectoryReturnsNil() throws {
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"

        XCTAssertNil(try AgentHooks.hookInvocation(for: .agy, workstreamID: UUID(), helperPath: helperPath))
    }

    func testHookInvocationForAgyWithWorkingDirectoryWritesHooks() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let id = try XCTUnwrap(UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC"))
        let helperPath = "/Applications/Dockyard's Debug.app/Contents/Helpers/dy-agent-state"
        let invocation = try XCTUnwrap(AgentHooks.hookInvocation(
            for: .agy,
            workstreamID: id,
            helperPath: helperPath,
            workingDirectory: tempDir.path
        ))

        let expectedURL = tempDir.appendingPathComponent(".agents/hooks.json")
        XCTAssertEqual(invocation.generatedConfigURL, expectedURL)
        XCTAssertEqual(invocation.commandConfigOverrides, [])
        XCTAssertEqual(invocation.commandFlags, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))

        let data = try Data(contentsOf: expectedURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let dockyardState = try XCTUnwrap(json["dockyard-state"] as? [String: Any])

        let preInvocation = try XCTUnwrap((dockyardState["PreInvocation"] as? [[String: Any]])?.first)
        XCTAssertEqual(preInvocation["type"] as? String, "command")
        let preInvocationCmd = try XCTUnwrap(preInvocation["command"] as? String)
        XCTAssertTrue(preInvocationCmd.contains("'/Applications/Dockyard'\\''s Debug.app/Contents/Helpers/dy-agent-state'"))
        XCTAssertTrue(preInvocationCmd.contains("--workstream-id aabbccdd-1122-3344-5566-778899aabbcc"))
        XCTAssertTrue(preInvocationCmd.contains("--state working"))

        let preToolUse = try XCTUnwrap((dockyardState["PreToolUse"] as? [[String: Any]])?.first)
        XCTAssertEqual(preToolUse["matcher"] as? String, "ask_question")
        let preToolHook = try XCTUnwrap((preToolUse["hooks"] as? [[String: Any]])?.first)
        let preToolCmd = try XCTUnwrap(preToolHook["command"] as? String)
        XCTAssertTrue(preToolCmd.contains("--state waiting"))

        let postToolUse = try XCTUnwrap((dockyardState["PostToolUse"] as? [[String: Any]])?.first)
        XCTAssertEqual(postToolUse["matcher"] as? String, "ask_question")
        let postToolHook = try XCTUnwrap((postToolUse["hooks"] as? [[String: Any]])?.first)
        let postToolCmd = try XCTUnwrap(postToolHook["command"] as? String)
        XCTAssertTrue(postToolCmd.contains("--state working"))

        let stop = try XCTUnwrap((dockyardState["Stop"] as? [[String: Any]])?.first)
        XCTAssertEqual(stop["type"] as? String, "command")
        let stopCmd = try XCTUnwrap(stop["command"] as? String)
        XCTAssertTrue(stopCmd.contains("--state idle"))
    }

    func testWriteAgyHooksPreservesExistingHooksAndRemoveCleansUp() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let hooksURL = tempDir.appendingPathComponent(".agents/hooks.json")
        let customHooks: [String: Any] = [
            "custom-linter": [
                "PostToolUse": [
                    ["matcher": "write_to_file", "hooks": [["type": "command", "command": "./lint.sh"]]],
                ],
            ],
        ]
        let customData = try JSONSerialization.data(withJSONObject: customHooks)
        try customData.write(to: hooksURL)

        let id = UUID()
        try AgentHooks.writeAgyHooks(workingDirectory: tempDir.path, workstreamID: id, helperPath: "/path/to/dy-agent-state")

        let mergedData = try Data(contentsOf: hooksURL)
        let mergedJson = try XCTUnwrap(JSONSerialization.jsonObject(with: mergedData) as? [String: Any])
        XCTAssertNotNil(mergedJson["custom-linter"])
        XCTAssertNotNil(mergedJson["dockyard-state"])

        AgentHooks.removeAgyHooks(workingDirectory: tempDir.path)

        let cleanedData = try Data(contentsOf: hooksURL)
        let cleanedJson = try XCTUnwrap(JSONSerialization.jsonObject(with: cleanedData) as? [String: Any])
        XCTAssertNotNil(cleanedJson["custom-linter"])
        XCTAssertNil(cleanedJson["dockyard-state"])
    }

    func testWriteAgyHooksIncludesSubagentHooks() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let id = UUID()
        let url = try XCTUnwrap(AgentHooks.writeAgyHooks(workingDirectory: tempDir.path, workstreamID: id, helperPath: "/path/to/dy-agent-state"))

        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let dockyardState = try XCTUnwrap(json["dockyard-state"] as? [String: Any])
        let postToolUse = try XCTUnwrap(dockyardState["PostToolUse"] as? [[String: Any]])

        let invokeSubagentHook = postToolUse.first { ($0["matcher"] as? String) == "invoke_subagent" }
        XCTAssertNotNil(invokeSubagentHook)
        let invokeCommand = ((invokeSubagentHook?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        XCTAssertTrue(invokeCommand?.contains("--subagent-event start") == true)

        let manageSubagentsHook = postToolUse.first { ($0["matcher"] as? String) == "manage_subagents" }
        XCTAssertNotNil(manageSubagentsHook)
        let manageCommand = ((manageSubagentsHook?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        XCTAssertTrue(manageCommand?.contains("--subagent-event stop") == true)
    }

    func testOpenCodeAutoRenameConfigurationReferencesGeneratedInstructionFile() throws {
        let id = try XCTUnwrap(UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC"))
        let content = try AgentHooks.openCodeAutoRenameConfiguration(workstreamID: id)
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        let instructionPath = try XCTUnwrap((config["instructions"] as? [String])?.first)

        XCTAssertTrue(instructionPath.contains("opencode-settings/aabbccdd-1122-3344-5566-778899aabbcc/auto-rename.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: instructionPath))
        XCTAssertTrue(try String(contentsOfFile: instructionPath).contains("git branch -m <type>/<description>"))
    }

    func testHookInvocationReturnsURLForClaude() throws {
        let id = UUID()
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"
        let invocation = try XCTUnwrap(AgentHooks.hookInvocation(for: .claude, workstreamID: id, helperPath: helperPath))

        XCTAssertEqual(invocation.generatedConfigURL, AgentHooks.settingsURL(for: id))
        XCTAssertEqual(invocation.commandConfigOverrides, [])
        XCTAssertEqual(invocation.commandFlags, [])
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(invocation.generatedConfigURL?.path)))
    }

    func testCodexHookInvocationBuildsThreeConfigOverrides() throws {
        let id = try XCTUnwrap(UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC"))
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"
        let invocation = try XCTUnwrap(AgentHooks.hookInvocation(for: .codex, workstreamID: id, helperPath: helperPath))

        XCTAssertNil(invocation.generatedConfigURL)
        XCTAssertEqual(invocation.commandFlags, ["--dangerously-bypass-hook-trust"])
        XCTAssertEqual(invocation.commandConfigOverrides.count, 3)

        XCTAssertTrue(invocation.commandConfigOverrides.contains { override in
            override.hasPrefix("hooks.UserPromptSubmit=")
                && override.contains("--workstream-id aabbccdd-1122-3344-5566-778899aabbcc")
                && override.contains("--state working")
        })
        XCTAssertTrue(invocation.commandConfigOverrides.contains { override in
            override.hasPrefix("hooks.PermissionRequest=")
                && override.contains("--state waiting")
        })
        XCTAssertTrue(invocation.commandConfigOverrides.contains { override in
            override.hasPrefix("hooks.Stop=")
                && override.contains("--state idle")
        })
    }

    func testCodexHookInvocationShellQuotesHelperPathWithSpacesAndApostrophes() throws {
        let id = try XCTUnwrap(UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC"))
        let helperPath = "/Applications/Dockyard's Debug.app/Contents/Helpers/dy-agent-state"
        let invocation = try XCTUnwrap(AgentHooks.hookInvocation(for: .codex, workstreamID: id, helperPath: helperPath))
        let joined = invocation.commandConfigOverrides.joined(separator: "\n")

        XCTAssertTrue(joined.contains("'/Applications/Dockyard'\\\\''s Debug.app/Contents/Helpers/dy-agent-state'"))
    }

    func testCodexHookInvocationEscapesTomlStringContent() throws {
        let id = UUID()
        let helperPath = "/tmp/quote\"and\\slash/dy-agent-state"
        let invocation = try XCTUnwrap(AgentHooks.hookInvocation(for: .codex, workstreamID: id, helperPath: helperPath))
        let joined = invocation.commandConfigOverrides.joined(separator: "\n")

        XCTAssertTrue(joined.contains("\\\""))
        XCTAssertTrue(joined.contains("\\\\slash"))
    }

    func testWriteSettingsProducesValidJSONWithChromeActivityHooks() throws {
        let id = try XCTUnwrap(UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC"))
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"
        let url = try AgentHooks.writeClaudeSettings(workstreamID: id, helperPath: helperPath)

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = json?["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["UserPromptSubmit"])
        XCTAssertNotNil(hooks?["Notification"])
        XCTAssertNotNil(hooks?["Stop"])
        XCTAssertNotNil(hooks?["SubagentStart"])
        XCTAssertNotNil(hooks?["SubagentStop"])
        XCTAssertNotNil(hooks?["PreToolUse"])
        XCTAssertNotNil(hooks?["PostToolUse"])

        // Verify the helper path and UUID are embedded in the UserPromptSubmit command.
        let userPrompt = (hooks?["UserPromptSubmit"] as? [[String: Any]])?.first
        let inner = (userPrompt?["hooks"] as? [[String: Any]])?.first
        let command = inner?["command"] as? String
        XCTAssertNotNil(command)
        XCTAssertTrue(try XCTUnwrap(command?.contains(helperPath)))
        XCTAssertTrue(try XCTUnwrap(command?.contains("aabbccdd-1122-3344-5566-778899aabbcc")))
        XCTAssertTrue(try XCTUnwrap(command?.contains("--state working")))

        let preToolUse = (hooks?["PreToolUse"] as? [[String: Any]])?.first
        XCTAssertEqual(preToolUse?["matcher"] as? String, "mcp__claude-in-chrome__.*")
        let preToolHook = (preToolUse?["hooks"] as? [[String: Any]])?.first
        XCTAssertTrue((preToolHook?["command"] as? String)?.contains("--chrome-active true") == true)

        let postToolUse = (hooks?["PostToolUse"] as? [[String: Any]])?.first
        XCTAssertEqual(postToolUse?["matcher"] as? String, "mcp__claude-in-chrome__.*")
        let postToolHook = (postToolUse?["hooks"] as? [[String: Any]])?.first
        XCTAssertTrue((postToolHook?["command"] as? String)?.contains("--chrome-active false") == true)

        let subagentStart = (hooks?["SubagentStart"] as? [[String: Any]])?.first
        let subagentStartHook = (subagentStart?["hooks"] as? [[String: Any]])?.first
        XCTAssertTrue((subagentStartHook?["command"] as? String)?.contains("--subagent-event start") == true)

        let subagentStop = (hooks?["SubagentStop"] as? [[String: Any]])?.first
        let subagentStopHook = (subagentStop?["hooks"] as? [[String: Any]])?.first
        XCTAssertTrue((subagentStopHook?["command"] as? String)?.contains("--subagent-event stop") == true)
    }

    func testHelperPathWithSpacesIsShellQuoted() throws {
        let id = UUID()
        let helperPath = "/path/with spaces/Dockyard Debug.app/Contents/Helpers/dy-agent-state"
        let url = try AgentHooks.writeClaudeSettings(workstreamID: id, helperPath: helperPath)

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = json?["hooks"] as? [String: Any]
        let userPrompt = (hooks?["UserPromptSubmit"] as? [[String: Any]])?.first
        let inner = (userPrompt?["hooks"] as? [[String: Any]])?.first
        let command = inner?["command"] as? String

        // The helper path must be wrapped in single quotes so /bin/sh -c treats
        // it as a single argv[0]. Without quoting, sh splits on the space and
        // tries to exec '/path/with' which fails.
        XCTAssertTrue(try XCTUnwrap(command?.hasPrefix("'\(helperPath)' ")), "expected single-quoted helper path, got: \(command!)")
    }

    func testHelperPathWithSingleQuoteIsEscaped() throws {
        let id = UUID()
        let helperPath = "/weird'path/dy-agent-state"
        let url = try AgentHooks.writeClaudeSettings(workstreamID: id, helperPath: helperPath)

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = json?["hooks"] as? [String: Any]
        let userPrompt = (hooks?["UserPromptSubmit"] as? [[String: Any]])?.first
        let inner = (userPrompt?["hooks"] as? [[String: Any]])?.first
        let command = inner?["command"] as? String

        // POSIX single-quote escape: ' becomes '\''
        XCTAssertTrue(try XCTUnwrap(command?.hasPrefix("'/weird'\\''path/dy-agent-state' ")), "got: \(command!)")
    }

    func testWriteAgyHooksThrowsOnCorruptedFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let hooksURL = tempDir.appendingPathComponent(".agents/hooks.json")
        try Data("[1, 2, 3]".utf8).write(to: hooksURL)

        XCTAssertThrowsError(try AgentHooks.writeAgyHooks(
            workingDirectory: tempDir.path,
            workstreamID: UUID(),
            helperPath: "/path/to/dy-agent-state"
        )) { error in
            XCTAssertEqual(error as? AgentHookError, .hooksFileCorrupted)
        }
    }

    func testWriteAgyHooksThrowsOnCollisionWithCustomDockyardState() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let hooksURL = tempDir.appendingPathComponent(".agents/hooks.json")
        let collisionHooks: [String: Any] = [
            "dockyard-state": [
                "PreInvocation": [
                    ["type": "command", "command": "./my-custom-script.sh"],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: collisionHooks)
        try data.write(to: hooksURL)

        XCTAssertThrowsError(try AgentHooks.writeAgyHooks(
            workingDirectory: tempDir.path,
            workstreamID: UUID(),
            helperPath: "/path/to/dy-agent-state"
        )) { error in
            XCTAssertEqual(error as? AgentHookError, .hookCollision("dockyard-state"))
        }

        // Verify removeAgyHooks leaves custom dockyard-state intact
        AgentHooks.removeAgyHooks(workingDirectory: tempDir.path)
        let remainingData = try Data(contentsOf: hooksURL)
        let remainingJson = try XCTUnwrap(JSONSerialization.jsonObject(with: remainingData) as? [String: Any])
        XCTAssertNotNil(remainingJson["dockyard-state"])
    }

    func testWriteAgyHooksDoesNotMutateTrackedHooksFile() throws {
        guard let gitPath = CommandLineTools.path(for: "git") else {
            throw XCTSkip("git not found")
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".agents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        func runGit(_ args: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: gitPath)
            p.arguments = args
            p.currentDirectoryURL = tempDir
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0)
        }

        try runGit(["init"])
        try runGit(["config", "user.name", "Test"])
        try runGit(["config", "user.email", "test@example.com"])

        let hooksURL = tempDir.appendingPathComponent(".agents/hooks.json")
        let originalContent = "{\n  \"tracked\" : true\n}"
        try Data(originalContent.utf8).write(to: hooksURL)
        try runGit(["add", ".agents/hooks.json"])
        try runGit(["commit", "-m", "add tracked hooks"])

        let id = UUID()
        let result = try AgentHooks.writeAgyHooks(
            workingDirectory: tempDir.path,
            workstreamID: id,
            helperPath: "/path/to/dy-agent-state"
        )
        XCTAssertNil(result)

        // Verify file content was not mutated
        let currentContent = try String(contentsOf: hooksURL)
        XCTAssertEqual(currentContent, originalContent)

        // Verify removeAgyHooks also does not mutate tracked file
        AgentHooks.removeAgyHooks(workingDirectory: tempDir.path)
        let afterRemoveContent = try String(contentsOf: hooksURL)
        XCTAssertEqual(afterRemoveContent, originalContent)
    }
}
