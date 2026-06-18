// ABOUTME: Tests AgentHooks settings.json generation and per-CLI capability matrix.

@testable import Dockyard
import XCTest

final class AgentHooksTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: AgentHooks.settingsDirectoryURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: AgentHooks.settingsDirectoryURL)
        super.tearDown()
    }

    func testHookInvocationReturnsNilForOpenCodeAndGemini() throws {
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"

        XCTAssertNil(try AgentHooks.hookInvocation(for: .opencode, workstreamID: UUID(), helperPath: helperPath))
        XCTAssertNil(try AgentHooks.hookInvocation(for: .gemini, workstreamID: UUID(), helperPath: helperPath))
    }

    func testHookInvocationReturnsURLForClaude() throws {
        let id = UUID()
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"
        let invocation = try XCTUnwrap(AgentHooks.hookInvocation(for: .claude, workstreamID: id, helperPath: helperPath))

        XCTAssertEqual(invocation.generatedConfigURL, AgentHooks.settingsURL(for: id))
        XCTAssertEqual(invocation.commandConfigOverrides, [])
        XCTAssertEqual(invocation.commandFlags, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: invocation.generatedConfigURL!.path))
    }

    func testCodexHookInvocationBuildsThreeConfigOverrides() throws {
        let id = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
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
        let id = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
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

    func testWriteSettingsProducesValidJSONWithThreeHooks() throws {
        let id = UUID(uuidString: "AABBCCDD-1122-3344-5566-778899AABBCC")!
        let helperPath = "/Applications/Dockyard.app/Contents/Helpers/dy-agent-state"
        let url = try AgentHooks.writeClaudeSettings(workstreamID: id, helperPath: helperPath)

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = json?["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["UserPromptSubmit"])
        XCTAssertNotNil(hooks?["Notification"])
        XCTAssertNotNil(hooks?["Stop"])

        // Verify the helper path and UUID are embedded in the UserPromptSubmit command.
        let userPrompt = (hooks?["UserPromptSubmit"] as? [[String: Any]])?.first
        let inner = (userPrompt?["hooks"] as? [[String: Any]])?.first
        let command = inner?["command"] as? String
        XCTAssertNotNil(command)
        XCTAssertTrue(command!.contains(helperPath))
        XCTAssertTrue(command!.contains("aabbccdd-1122-3344-5566-778899aabbcc"))
        XCTAssertTrue(command!.contains("--state working"))
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
        XCTAssertTrue(command!.hasPrefix("'\(helperPath)' "), "expected single-quoted helper path, got: \(command!)")
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
        XCTAssertTrue(command!.hasPrefix("'/weird'\\''path/dy-agent-state' "), "got: \(command!)")
    }
}
