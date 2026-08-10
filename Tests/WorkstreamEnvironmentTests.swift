// ABOUTME: Tests for WorkstreamEnvironment env var construction.
// ABOUTME: Validates DY_* vars, default branch, and compatibility aliases for external tools.

@testable import Dockyard
import XCTest

final class WorkstreamEnvironmentTests: XCTestCase {
    private let baseParams: (UUID, String, String, String, String, Int, Bool) = (
        UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
        "my-project",
        "coral-reef",
        "/Users/test/my-project",
        "/Users/test/.dockyard/worktrees/my-project/coral-reef",
        42847,
        false
    )

    // MARK: - Core DY_* variables

    func testCoreVariables() {
        let vars = WorkstreamEnvironment.variables(
            workstreamID: baseParams.0,
            projectName: baseParams.1,
            workstreamName: baseParams.2,
            projectDirectory: baseParams.3,
            workingDirectory: baseParams.4,
            port: baseParams.5,
            codingCLI: .claude,
            agentTeams: baseParams.6,
            defaultBranch: "main",
            scriptSource: nil
        )
        XCTAssertEqual(vars["DY_WORKSTREAM_ID"], "12345678-1234-1234-1234-123456789abc")
        XCTAssertEqual(vars["DY_PROJECT"], "my-project")
        XCTAssertEqual(vars["DY_WORKSTREAM"], "coral-reef")
        XCTAssertEqual(vars["DY_PROJECT_DIR"], "/Users/test/my-project")
        XCTAssertEqual(vars["DY_WORKTREE_DIR"], "/Users/test/.dockyard/worktrees/my-project/coral-reef")
        XCTAssertEqual(vars["DY_PORT"], "42847")
        XCTAssertEqual(vars["DY_DEFAULT_BRANCH"], "main")
        XCTAssertNil(vars["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"])
    }

    func testAgentTeamsFlag() {
        let vars = WorkstreamEnvironment.variables(
            workstreamID: baseParams.0,
            projectName: baseParams.1,
            workstreamName: baseParams.2,
            projectDirectory: baseParams.3,
            workingDirectory: baseParams.4,
            port: baseParams.5,
            codingCLI: .claude,
            agentTeams: true,
            defaultBranch: "main",
            scriptSource: nil
        )
        XCTAssertEqual(vars["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"], "1")
    }

    // MARK: - Conductor aliases

    func testConductorAliases() {
        let vars = WorkstreamEnvironment.variables(
            workstreamID: baseParams.0,
            projectName: baseParams.1,
            workstreamName: baseParams.2,
            projectDirectory: baseParams.3,
            workingDirectory: baseParams.4,
            port: baseParams.5,
            codingCLI: .claude,
            agentTeams: baseParams.6,
            defaultBranch: "main",
            scriptSource: "conductor.json"
        )
        XCTAssertEqual(vars["CONDUCTOR_WORKSPACE_NAME"], "coral-reef")
        XCTAssertEqual(vars["CONDUCTOR_ROOT_PATH"], "/Users/test/my-project")
        XCTAssertEqual(vars["CONDUCTOR_WORKSPACE_PATH"], "/Users/test/.dockyard/worktrees/my-project/coral-reef")
        XCTAssertEqual(vars["CONDUCTOR_PORT"], "42847")
        XCTAssertEqual(vars["CONDUCTOR_DEFAULT_BRANCH"], "main")
    }

    // MARK: - Emdash aliases

    func testEmdashAliases() {
        let vars = WorkstreamEnvironment.variables(
            workstreamID: baseParams.0,
            projectName: baseParams.1,
            workstreamName: baseParams.2,
            projectDirectory: baseParams.3,
            workingDirectory: baseParams.4,
            port: baseParams.5,
            codingCLI: .claude,
            agentTeams: baseParams.6,
            defaultBranch: "develop",
            scriptSource: ".emdash.json"
        )
        XCTAssertEqual(vars["EMDASH_TASK_ID"], "12345678-1234-1234-1234-123456789abc")
        XCTAssertEqual(vars["EMDASH_TASK_NAME"], "coral-reef")
        XCTAssertEqual(vars["EMDASH_TASK_PATH"], "/Users/test/.dockyard/worktrees/my-project/coral-reef")
        XCTAssertEqual(vars["EMDASH_ROOT_PATH"], "/Users/test/my-project")
        XCTAssertEqual(vars["EMDASH_PORT"], "42847")
        XCTAssertEqual(vars["EMDASH_DEFAULT_BRANCH"], "develop")
    }

    // MARK: - Superset aliases

    func testSupersetAliases() {
        let vars = WorkstreamEnvironment.variables(
            workstreamID: baseParams.0,
            projectName: baseParams.1,
            workstreamName: baseParams.2,
            projectDirectory: baseParams.3,
            workingDirectory: baseParams.4,
            port: baseParams.5,
            codingCLI: .claude,
            agentTeams: baseParams.6,
            defaultBranch: "main",
            scriptSource: ".superset/config.json"
        )
        XCTAssertEqual(vars["SUPERSET_WORKSPACE_NAME"], "coral-reef")
        XCTAssertEqual(vars["SUPERSET_ROOT_PATH"], "/Users/test/my-project")
        XCTAssertEqual(vars["SUPERSET_PORT_BASE"], "42847")
    }

    // MARK: - No aliases for native config

    func testNoAliasesForDockyardConfig() {
        let vars = WorkstreamEnvironment.variables(
            workstreamID: baseParams.0,
            projectName: baseParams.1,
            workstreamName: baseParams.2,
            projectDirectory: baseParams.3,
            workingDirectory: baseParams.4,
            port: baseParams.5,
            codingCLI: .claude,
            agentTeams: baseParams.6,
            defaultBranch: "main",
            scriptSource: ".dockyard.json"
        )
        XCTAssertNil(vars["CONDUCTOR_WORKSPACE_NAME"])
        XCTAssertNil(vars["EMDASH_TASK_NAME"])
        XCTAssertNil(vars["SUPERSET_WORKSPACE_NAME"])
    }

    func testNoAliasesForNilSource() {
        let vars = WorkstreamEnvironment.variables(
            workstreamID: baseParams.0,
            projectName: baseParams.1,
            workstreamName: baseParams.2,
            projectDirectory: baseParams.3,
            workingDirectory: baseParams.4,
            port: baseParams.5,
            codingCLI: .claude,
            agentTeams: baseParams.6,
            defaultBranch: "main",
            scriptSource: nil
        )
        XCTAssertNil(vars["CONDUCTOR_WORKSPACE_NAME"])
        XCTAssertNil(vars["EMDASH_TASK_NAME"])
        XCTAssertNil(vars["SUPERSET_WORKSPACE_NAME"])
    }

    // MARK: - Automatic development environments

    func testContainedEnvironmentPathsKeepVenvPrecedence() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("project", isDirectory: true)
        let venvBin = project.appendingPathComponent("venv/bin", isDirectory: true)
        let dotVenvBin = project.appendingPathComponent(".venv/bin", isDirectory: true)
        let nodeBin = project.appendingPathComponent("node_modules/.bin", isDirectory: true)
        try createActivationFile(in: venvBin)
        try createActivationFile(in: dotVenvBin)
        try FileManager.default.createDirectory(at: nodeBin, withIntermediateDirectories: true)

        let script = RunLauncher.wrapWithVenv("python app.py", projectDirectory: project.path)
        XCTAssertTrue(script.hasPrefix("source \(CommandBuilder.shellQuote(venvBin.appendingPathComponent("activate").path))"))
        XCTAssertFalse(script.contains(dotVenvBin.path))

        let vars = variables(projectDirectory: project.path)
        let prependedPaths = try XCTUnwrap(vars["PATH"]?.split(separator: ":").map(String.init))
        XCTAssertEqual(Array(prependedPaths.prefix(2)), [venvBin.path, nodeBin.path])
        XCTAssertFalse(vars["PATH"]?.contains(dotVenvBin.path) ?? true)
    }

    func testEscapingVenvFallsBackToContainedDotVenv() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("project", isDirectory: true)
        let outsideVenv = root.appendingPathComponent("outside-venv", isDirectory: true)
        let dotVenvBin = project.appendingPathComponent(".venv/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try createActivationFile(in: outsideVenv.appendingPathComponent("bin", isDirectory: true))
        try createActivationFile(in: dotVenvBin)
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("venv"),
            withDestinationURL: outsideVenv
        )

        let script = RunLauncher.wrapWithVenv("python app.py", projectDirectory: project.path)
        XCTAssertTrue(script.hasPrefix("source \(CommandBuilder.shellQuote(dotVenvBin.appendingPathComponent("activate").path))"))
        XCTAssertFalse(script.contains(outsideVenv.path))

        let prependedPaths = variables(projectDirectory: project.path)["PATH"]?
            .split(separator: ":")
            .map(String.init)
        XCTAssertEqual(prependedPaths?.first, dotVenvBin.path)
        XCTAssertFalse(prependedPaths?.contains(outsideVenv.appendingPathComponent("bin").path) ?? true)
    }

    func testEscapingEnvironmentSymlinksAreIgnored() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("project", isDirectory: true)
        let outsideVenv = root.appendingPathComponent("outside-venv", isDirectory: true)
        let outsideNodeModules = root.appendingPathComponent("outside-node-modules", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try createActivationFile(in: outsideVenv.appendingPathComponent("bin", isDirectory: true))
        try FileManager.default.createDirectory(
            at: outsideNodeModules.appendingPathComponent(".bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("venv"),
            withDestinationURL: outsideVenv
        )
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("node_modules"),
            withDestinationURL: outsideNodeModules
        )

        XCTAssertEqual(
            RunLauncher.wrapWithVenv("python app.py", projectDirectory: project.path),
            "python app.py"
        )
        XCTAssertNil(variables(projectDirectory: project.path)["PATH"])
    }

    func testContainedSymlinksWorkThroughSymlinkedProjectRoot() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("real-project", isDirectory: true)
        let projectAlias = root.appendingPathComponent("project-alias", isDirectory: true)
        let sharedVenv = project.appendingPathComponent("shared-venv", isDirectory: true)
        let sharedNodeBin = project.appendingPathComponent("shared-node-bin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("node_modules", isDirectory: true),
            withIntermediateDirectories: true
        )
        try createActivationFile(in: sharedVenv.appendingPathComponent("bin", isDirectory: true))
        try FileManager.default.createDirectory(at: sharedNodeBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("venv"),
            withDestinationURL: sharedVenv
        )
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("node_modules/.bin"),
            withDestinationURL: sharedNodeBin
        )
        try FileManager.default.createSymbolicLink(at: projectAlias, withDestinationURL: project)

        let activation = sharedVenv.appendingPathComponent("bin/activate").path
        let script = RunLauncher.wrapWithVenv("python app.py", projectDirectory: projectAlias.path)
        XCTAssertTrue(script.hasPrefix("source \(CommandBuilder.shellQuote(activation))"))

        let prependedPaths = try XCTUnwrap(
            variables(projectDirectory: projectAlias.path)["PATH"]?
                .split(separator: ":")
                .map(String.init)
        )
        XCTAssertEqual(
            Array(prependedPaths.prefix(2)),
            [sharedVenv.appendingPathComponent("bin").path, sharedNodeBin.path]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-environment-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func createActivationFile(in binDirectory: URL) throws {
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try "# contained test environment\n".write(
            to: binDirectory.appendingPathComponent("activate"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func variables(projectDirectory: String) -> [String: String] {
        WorkstreamEnvironment.variables(
            workstreamID: baseParams.0,
            projectName: baseParams.1,
            workstreamName: baseParams.2,
            projectDirectory: projectDirectory,
            workingDirectory: baseParams.4,
            port: baseParams.5,
            codingCLI: .claude,
            agentTeams: baseParams.6,
            defaultBranch: "main",
            scriptSource: nil
        )
    }
}
