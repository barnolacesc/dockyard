// ABOUTME: Tests for StackDetector, which infers a .dockyard.json draft from repo files.
// ABOUTME: One case per supported stack plus the ordered JSON serialization of the draft.

@testable import Dockyard
import XCTest

final class StackDetectorTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Empty

    func testEmptyDirectoryReturnsEmptyDraft() {
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertTrue(draft.isEmpty)
        XCTAssertNil(draft.setup)
        XCTAssertNil(draft.run)
    }

    // MARK: - Node / TS

    func testNodeNpmDefault() {
        writePackageJSON(scripts: ["dev": "vite"])
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "npm install")
        XCTAssertEqual(draft.run, "npm run dev")
    }

    func testNodePnpmFromLockfile() {
        writePackageJSON(scripts: ["dev": "vite"])
        touch("pnpm-lock.yaml")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "pnpm install")
        XCTAssertEqual(draft.run, "pnpm run dev")
    }

    func testNodeYarnFromLockfile() {
        writePackageJSON(scripts: ["dev": "next dev"], deps: ["next": "14"])
        touch("yarn.lock")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "yarn install")
        XCTAssertEqual(draft.run, "yarn run dev")
        XCTAssertEqual(draft.expectedPort, 3000)
    }

    func testNodeBunFallsBackToStartScript() {
        writePackageJSON(scripts: ["start": "node server.js"])
        touch("bun.lockb")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "bun install")
        XCTAssertEqual(draft.run, "bun run start")
    }

    func testNodeVitePort() {
        writePackageJSON(scripts: ["dev": "vite"], devDeps: ["vite": "5"])
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.expectedPort, 5173)
    }

    func testNodeAstroPort() {
        writePackageJSON(scripts: ["dev": "astro dev"], deps: ["astro": "4"])
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.expectedPort, 4321)
    }

    // MARK: - Python (uv)

    func testPythonUvDjango() {
        touch("pyproject.toml", "[project]\ndependencies = [\"django\"]\n")
        touch("uv.lock")
        touch("manage.py")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "uv sync")
        XCTAssertEqual(draft.run, "uv run python manage.py runserver")
        XCTAssertEqual(draft.expectedPort, 8000)
    }

    func testPythonUvFastAPI() {
        touch("pyproject.toml", "[project]\ndependencies = [\"fastapi\"]\n")
        touch("uv.lock")
        touch("main.py")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "uv sync")
        XCTAssertEqual(draft.run, "uv run uvicorn main:app --reload")
        XCTAssertEqual(draft.expectedPort, 8000)
    }

    // MARK: - Python (pip)

    func testPythonPipDjango() {
        touch("requirements.txt", "django\n")
        touch("manage.py")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "python -m venv .venv && .venv/bin/pip install -r requirements.txt")
        XCTAssertEqual(draft.run, ".venv/bin/python manage.py runserver")
        XCTAssertEqual(draft.expectedPort, 8000)
    }

    func testPythonPipFlaskPort() {
        touch("requirements.txt", "flask\n")
        touch("app.py")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.run, ".venv/bin/flask run")
        XCTAssertEqual(draft.expectedPort, 5000)
    }

    // MARK: - Python (bare)

    func testPythonBareDjango() {
        touch("manage.py")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "uv venv && uv pip install django")
        XCTAssertEqual(draft.run, ".venv/bin/python manage.py runserver")
        XCTAssertEqual(draft.expectedPort, 8000)
    }

    // MARK: - Rust / Go

    func testRust() {
        touch("Cargo.toml")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "cargo fetch")
        XCTAssertEqual(draft.run, "cargo run")
    }

    func testGo() {
        touch("go.mod")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "go mod download")
        XCTAssertEqual(draft.run, "go run .")
    }

    // MARK: - Ruby / Elixir

    func testRubyRails() {
        touch("Gemfile", "gem \"rails\"\n")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "bundle install")
        XCTAssertEqual(draft.run, "bin/rails server")
        XCTAssertEqual(draft.expectedPort, 3000)
    }

    func testElixirPhoenix() {
        touch("mix.exs", "defp deps do [{:phoenix, \"~> 1.7\"}] end\n")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "mix deps.get")
        XCTAssertEqual(draft.run, "mix phx.server")
        XCTAssertEqual(draft.expectedPort, 4000)
    }

    // MARK: - Docker Compose (combined)

    func testDockerComposeWithUvPython() {
        touch("docker-compose.yml")
        touch("pyproject.toml", "[project]\ndependencies = [\"django\"]\n")
        touch("uv.lock")
        touch("manage.py")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "docker compose up -d && uv sync")
        XCTAssertEqual(draft.run, "uv run python manage.py runserver")
        XCTAssertEqual(draft.teardown, "docker compose down")
        XCTAssertEqual(draft.expectedPort, 8000)
    }

    func testDockerComposeAloneSetsTeardown() {
        touch("compose.yml")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "docker compose up -d")
        XCTAssertEqual(draft.teardown, "docker compose down")
    }

    // MARK: - Makefile

    func testMakefilePrefersTargets() {
        touch("Makefile", "setup:\n\tnpm ci\n\ndev:\n\tnpm run dev\n")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "make setup")
        XCTAssertEqual(draft.run, "make dev")
    }

    func testMakefileOverridesNodeSetup() {
        writePackageJSON(scripts: ["dev": "vite"])
        touch("Makefile", "setup:\n\tnpm ci\n")
        let draft = StackDetector.detect(at: tmpDir.path)
        XCTAssertEqual(draft.setup, "make setup")
    }

    // MARK: - Metadata containment

    func testContainedPackageManifestSymlinkIsDetected() throws {
        let metadataDirectory = tmpDir.appendingPathComponent("metadata")
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        let package = metadataDirectory.appendingPathComponent("package.json")
        let object: [String: Any] = [
            "name": "app",
            "scripts": ["dev": "vite"],
            "devDependencies": ["vite": "5"],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: package)
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent("package.json"),
            withDestinationURL: package
        )

        let draft = StackDetector.detect(at: tmpDir.path)

        XCTAssertEqual(draft.setup, "npm install")
        XCTAssertEqual(draft.run, "npm run dev")
        XCTAssertEqual(draft.expectedPort, 5173)
    }

    func testEscapingPackageManifestSymlinkIsIgnored() throws {
        let externalDirectory = try makeExternalDirectory()
        defer { try? FileManager.default.removeItem(at: externalDirectory) }
        let package = externalDirectory.appendingPathComponent("package.json")
        let object: [String: Any] = [
            "name": "outside",
            "scripts": ["dev": "vite"],
            "devDependencies": ["vite": "5"],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: package)
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent("package.json"),
            withDestinationURL: package
        )

        let draft = StackDetector.detect(at: tmpDir.path)

        XCTAssertTrue(draft.isEmpty)
    }

    func testEscapingLockfileSymlinkDoesNotSelectPackageManager() throws {
        writePackageJSON(scripts: ["dev": "vite"])
        let externalDirectory = try makeExternalDirectory()
        defer { try? FileManager.default.removeItem(at: externalDirectory) }
        let lockfile = externalDirectory.appendingPathComponent("pnpm-lock.yaml")
        try Data().write(to: lockfile)
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent("pnpm-lock.yaml"),
            withDestinationURL: lockfile
        )

        let draft = StackDetector.detect(at: tmpDir.path)

        XCTAssertEqual(draft.setup, "npm install")
        XCTAssertEqual(draft.run, "npm run dev")
    }

    func testEscapingNestedMetadataSymlinkDoesNotInferRails() throws {
        touch("Gemfile", "gem \"rack\"\n")
        let externalDirectory = try makeExternalDirectory()
        defer { try? FileManager.default.removeItem(at: externalDirectory) }
        touch(at: externalDirectory.appendingPathComponent("rails"))
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent("bin"),
            withDestinationURL: externalDirectory
        )

        let draft = StackDetector.detect(at: tmpDir.path)

        XCTAssertEqual(draft.setup, "bundle install")
        XCTAssertNil(draft.run)
        XCTAssertNil(draft.expectedPort)
    }

    func testEscapingComposeManifestSymlinkIsIgnored() throws {
        let externalDirectory = try makeExternalDirectory()
        defer { try? FileManager.default.removeItem(at: externalDirectory) }
        let compose = externalDirectory.appendingPathComponent("compose.yml")
        try Data("services: {}\n".utf8).write(to: compose)
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent("compose.yml"),
            withDestinationURL: compose
        )

        let draft = StackDetector.detect(at: tmpDir.path)

        XCTAssertTrue(draft.isEmpty)
        XCTAssertNil(draft.teardown)
    }

    func testSymlinkedProjectRootRemainsDetected() throws {
        let projectDirectory = tmpDir.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let package = projectDirectory.appendingPathComponent("package.json")
        let object: [String: Any] = [
            "name": "app",
            "scripts": ["start": "node server.js"],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: package)
        let projectLink = tmpDir.appendingPathComponent("project-link")
        try FileManager.default.createSymbolicLink(at: projectLink, withDestinationURL: projectDirectory)

        let draft = StackDetector.detect(at: projectLink.path)

        XCTAssertEqual(draft.setup, "npm install")
        XCTAssertEqual(draft.run, "npm run start")
    }

    // MARK: - JSON serialization

    func testJSONStringLogicalKeyOrder() {
        let draft = DockyardConfigDraft(
            setup: "docker compose up -d && uv sync",
            run: "uv run python manage.py runserver",
            teardown: "docker compose down",
            expectedPort: 8000
        )
        let expected = """
        {
          "setup": "docker compose up -d && uv sync",
          "run": "uv run python manage.py runserver",
          "teardown": "docker compose down",
          "expectedPort": 8000
        }

        """
        XCTAssertEqual(draft.jsonString(), expected)
    }

    func testJSONStringOmitsNilKeys() {
        let draft = DockyardConfigDraft(setup: "npm install", run: "npm run dev", teardown: nil, expectedPort: nil)
        let expected = """
        {
          "setup": "npm install",
          "run": "npm run dev"
        }

        """
        XCTAssertEqual(draft.jsonString(), expected)
    }

    // MARK: - Field parsing

    func testFieldParserTrimsCommandsAndPort() {
        let result = DockyardConfigDraft.parseFields(
            setup: "  npm install  ",
            run: "\tnpm run dev\n",
            teardown: "  docker compose down  ",
            portText: " 5173 "
        )

        XCTAssertNil(result.validationError)
        XCTAssertEqual(result.draft.setup, "npm install")
        XCTAssertEqual(result.draft.run, "npm run dev")
        XCTAssertEqual(result.draft.teardown, "docker compose down")
        XCTAssertEqual(result.draft.expectedPort, 5173)
    }

    func testFieldParserConvertsEmptyStringsToNil() {
        let result = DockyardConfigDraft.parseFields(
            setup: "   ",
            run: "npm run dev",
            teardown: "\n\t",
            portText: ""
        )

        XCTAssertNil(result.validationError)
        XCTAssertNil(result.draft.setup)
        XCTAssertEqual(result.draft.run, "npm run dev")
        XCTAssertNil(result.draft.teardown)
        XCTAssertNil(result.draft.expectedPort)
    }

    func testFieldParserAcceptsEmptyPort() {
        let result = DockyardConfigDraft.parseFields(
            setup: "",
            run: "make dev",
            teardown: "",
            portText: "   "
        )

        XCTAssertNil(result.validationError)
        XCTAssertEqual(result.draft.run, "make dev")
        XCTAssertNil(result.draft.expectedPort)
    }

    func testFieldParserRejectsNonIntegerPort() {
        let result = DockyardConfigDraft.parseFields(
            setup: "",
            run: "make dev",
            teardown: "",
            portText: "localhost"
        )

        XCTAssertEqual(result.validationError, .invalidPort)
        XCTAssertEqual(result.draft.run, "make dev")
        XCTAssertNil(result.draft.expectedPort)
    }

    func testFieldParserRejectsOutOfRangePort() {
        let low = DockyardConfigDraft.parseFields(setup: "", run: "make dev", teardown: "", portText: "0")
        let high = DockyardConfigDraft.parseFields(setup: "", run: "make dev", teardown: "", portText: "65536")

        XCTAssertEqual(low.validationError, .invalidPort)
        XCTAssertEqual(high.validationError, .invalidPort)
        XCTAssertNil(low.draft.expectedPort)
        XCTAssertNil(high.draft.expectedPort)
    }

    func testFieldParserAllEmptyProducesEmptyDraft() {
        let result = DockyardConfigDraft.parseFields(
            setup: " ",
            run: "",
            teardown: "\t",
            portText: "\n"
        )

        XCTAssertNil(result.validationError)
        XCTAssertTrue(result.draft.isEmpty)
    }

    // MARK: - Writer round-trips through ScriptConfig

    func testWriterProducesLoadableConfig() throws {
        let draft = DockyardConfigDraft(setup: "uv sync", run: "uv run python manage.py runserver", teardown: nil, expectedPort: 8000)
        try DockyardConfigWriter.write(draft, to: tmpDir.path)

        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.setup, "uv sync")
        XCTAssertEqual(config.run, "uv run python manage.py runserver")
        XCTAssertEqual(config.expectedPort, 8000)
        XCTAssertEqual(config.source, ".dockyard.json")
    }

    // MARK: - Helpers

    private func touch(_ name: String, _ contents: String = "") {
        let path = tmpDir.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: contents.data(using: .utf8))
    }

    private func touch(at url: URL, _ contents: String = "") {
        FileManager.default.createFile(atPath: url.path, contents: contents.data(using: .utf8))
    }

    private func makeExternalDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePackageJSON(scripts: [String: String], deps: [String: String] = [:], devDeps: [String: String] = [:]) {
        var obj: [String: Any] = ["name": "app", "scripts": scripts]
        if !deps.isEmpty { obj["dependencies"] = deps }
        if !devDeps.isEmpty { obj["devDependencies"] = devDeps }
        let data = try! JSONSerialization.data(withJSONObject: obj)
        FileManager.default.createFile(atPath: tmpDir.appendingPathComponent("package.json").path, contents: data)
    }
}
