// ABOUTME: Tests for ScriptConfig loading from multiple config file formats.
// ABOUTME: Validates priority order and parsing of dockyard, emdash, conductor, and superset configs.

@testable import Dockyard
import XCTest

final class ScriptConfigTests: XCTestCase {
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

    // MARK: - Empty directory

    func testEmptyDirectoryReturnsEmpty() {
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertNil(config.setup)
        XCTAssertNil(config.run)
        XCTAssertNil(config.teardown)
        XCTAssertNil(config.source)
        XCTAssertFalse(config.hasAnyScript)
    }

    // MARK: - .dockyard.json (primary)

    func testDockyardJSON() {
        writeJSON(".dockyard.json", ["setup": "npm install", "run": "npm start"])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.setup, "npm install")
        XCTAssertEqual(config.run, "npm start")
        XCTAssertNil(config.teardown)
        XCTAssertEqual(config.source, ".dockyard.json")
    }

    func testDockyardTakesPriorityOverConductor() {
        writeJSON(".dockyard.json", ["run": "dy-run"])
        writeJSON("conductor.json", ["scripts": ["run": "conductor-run"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.run, "dy-run")
        XCTAssertEqual(config.source, ".dockyard.json")
    }

    func testDockyardTakesPriorityOverSuperset() throws {
        writeJSON(".dockyard.json", ["run": "dy-run"])
        let supersetDir = tmpDir.appendingPathComponent(".superset")
        try FileManager.default.createDirectory(at: supersetDir, withIntermediateDirectories: true)
        writeJSON(".superset/config.json", ["run": ["superset-run"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.run, "dy-run")
        XCTAssertEqual(config.source, ".dockyard.json")
    }

    // MARK: - conductor.json (fallback)

    func testConductorJSON() {
        writeJSON("conductor.json", ["scripts": ["setup": "make build", "run": "make serve", "archive": "make clean"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.setup, "make build")
        XCTAssertEqual(config.run, "make serve")
        XCTAssertEqual(config.teardown, "make clean")
        XCTAssertEqual(config.source, "conductor.json")
    }

    func testConductorMapsArchiveToTeardown() {
        writeJSON("conductor.json", ["scripts": ["archive": "rm -rf dist"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.teardown, "rm -rf dist")
        XCTAssertNil(config.setup)
        XCTAssertNil(config.run)
    }

    func testConductorWithoutScriptsKeyReturnsEmpty() {
        writeJSON("conductor.json", ["setup": "npm install"])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertFalse(config.hasAnyScript)
    }

    func testConductorTakesPriorityOverSuperset() throws {
        writeJSON("conductor.json", ["scripts": ["run": "conductor-run"]])
        let supersetDir = tmpDir.appendingPathComponent(".superset")
        try FileManager.default.createDirectory(at: supersetDir, withIntermediateDirectories: true)
        writeJSON(".superset/config.json", ["run": ["superset-run"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.run, "conductor-run")
        XCTAssertEqual(config.source, "conductor.json")
    }

    // MARK: - .superset/config.json (fallback)

    func testSupersetJSON() throws {
        let supersetDir = tmpDir.appendingPathComponent(".superset")
        try FileManager.default.createDirectory(at: supersetDir, withIntermediateDirectories: true)
        writeJSON(".superset/config.json", ["setup": ["npm install", "cp .env.example .env"], "run": ["npm run dev"], "teardown": ["rm -rf node_modules"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.setup, "npm install && cp .env.example .env")
        XCTAssertEqual(config.run, "npm run dev")
        XCTAssertEqual(config.teardown, "rm -rf node_modules")
        XCTAssertEqual(config.source, ".superset/config.json")
    }

    func testSupersetFiltersEmptyStrings() throws {
        let supersetDir = tmpDir.appendingPathComponent(".superset")
        try FileManager.default.createDirectory(at: supersetDir, withIntermediateDirectories: true)
        writeJSON(".superset/config.json", ["run": ["npm start", "", "  "]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.run, "npm start")
    }

    func testSupersetAcceptsPlainStrings() throws {
        let supersetDir = tmpDir.appendingPathComponent(".superset")
        try FileManager.default.createDirectory(at: supersetDir, withIntermediateDirectories: true)
        writeJSON(".superset/config.json", ["run": "npm start"])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.run, "npm start")
    }

    // MARK: - .emdash.json (fallback)

    func testEmdashJSON() {
        writeJSON(".emdash.json", ["scripts": ["setup": "npm install", "run": "npm start", "teardown": "npm run clean"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.setup, "npm install")
        XCTAssertEqual(config.run, "npm start")
        XCTAssertEqual(config.teardown, "npm run clean")
        XCTAssertEqual(config.source, ".emdash.json")
    }

    func testEmdashWithoutScriptsKeyReturnsEmpty() {
        writeJSON(".emdash.json", ["setup": "npm install"])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertFalse(config.hasAnyScript)
    }

    func testDockyardTakesPriorityOverEmdash() {
        writeJSON(".dockyard.json", ["run": "dy-run"])
        writeJSON(".emdash.json", ["scripts": ["run": "emdash-run"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.run, "dy-run")
        XCTAssertEqual(config.source, ".dockyard.json")
    }

    func testEmdashTakesPriorityOverConductor() {
        writeJSON(".emdash.json", ["scripts": ["run": "emdash-run"]])
        writeJSON("conductor.json", ["scripts": ["run": "conductor-run"]])
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertEqual(config.run, "emdash-run")
        XCTAssertEqual(config.source, ".emdash.json")
    }

    func testInvalidEmdashJSONReportsError() {
        let path = tmpDir.appendingPathComponent(".emdash.json").path
        FileManager.default.createFile(atPath: path, contents: "not json".data(using: .utf8))
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertNotNil(config.loadError)
        XCTAssertEqual(config.source, ".emdash.json")
    }

    // MARK: - Error handling

    func testInvalidJSONReportsError() {
        let path = tmpDir.appendingPathComponent(".dockyard.json").path
        FileManager.default.createFile(atPath: path, contents: "not json".data(using: .utf8))
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertNotNil(config.loadError)
        XCTAssertEqual(config.source, ".dockyard.json")
    }

    func testInvalidConductorJSONReportsError() {
        let path = tmpDir.appendingPathComponent("conductor.json").path
        FileManager.default.createFile(atPath: path, contents: "not json".data(using: .utf8))
        let config = ScriptConfig.load(from: tmpDir.path)
        XCTAssertNotNil(config.loadError)
        XCTAssertEqual(config.source, "conductor.json")
    }

    // MARK: - Project containment

    func testRejectsConfigSymlinkOutsideProjectDirectory() throws {
        let outsideDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outsideDirectory) }
        let outsideConfig = outsideDirectory.appendingPathComponent("outside.json")
        writeJSON(at: outsideConfig, ["run": "outside-command"])
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent(".dockyard.json"),
            withDestinationURL: outsideConfig
        )

        let config = ScriptConfig.load(from: tmpDir.path)

        XCTAssertFalse(config.hasAnyScript)
        XCTAssertEqual(config.source, ".dockyard.json")
        XCTAssertNotNil(config.loadError)
    }

    func testRejectsConfigThroughEscapingAncestorSymlink() throws {
        let outsideDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outsideDirectory) }
        writeJSON(at: outsideDirectory.appendingPathComponent("config.json"), ["run": "outside-command"])
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent(".superset"),
            withDestinationURL: outsideDirectory
        )

        let config = ScriptConfig.load(from: tmpDir.path)

        XCTAssertFalse(config.hasAnyScript)
        XCTAssertEqual(config.source, ".superset/config.json")
        XCTAssertNotNil(config.loadError)
    }

    func testLoadsConfigSymlinkThatResolvesInsideProjectDirectory() throws {
        let target = tmpDir.appendingPathComponent("scripts.json")
        writeJSON(at: target, ["run": "inside-command"])
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent(".dockyard.json"),
            withDestinationURL: target
        )

        let config = ScriptConfig.load(from: tmpDir.path)

        XCTAssertEqual(config.run, "inside-command")
        XCTAssertEqual(config.source, ".dockyard.json")
        XCTAssertNil(config.loadError)
    }

    func testLoadsConfigThroughSymlinkedProjectDirectory() throws {
        let realProject = tmpDir.appendingPathComponent("real-project")
        try FileManager.default.createDirectory(at: realProject, withIntermediateDirectories: true)
        writeJSON(at: realProject.appendingPathComponent(".dockyard.json"), ["run": "inside-command"])
        let projectLink = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: projectLink) }
        try FileManager.default.createSymbolicLink(at: projectLink, withDestinationURL: realProject)

        let config = ScriptConfig.load(from: projectLink.path)

        XCTAssertEqual(config.run, "inside-command")
        XCTAssertEqual(config.source, ".dockyard.json")
        XCTAssertNil(config.loadError)
    }

    func testLoadsContainedConfigFromFallbackDirectory() {
        let fallbackDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: fallbackDirectory) }
        writeJSON(at: fallbackDirectory.appendingPathComponent(".dockyard.json"), ["run": "fallback-command"])

        let config = ScriptConfig.load(from: tmpDir.path, fallbackDirectory: fallbackDirectory.path)

        XCTAssertEqual(config.run, "fallback-command")
        XCTAssertEqual(config.source, ".dockyard.json")
        XCTAssertNil(config.loadError)
    }

    func testApprovedFingerprintCannotExecuteEscapingTeardownConfig() throws {
        let defaults = UserDefaults(suiteName: "ScriptConfigContainmentTests")!
        defaults.removePersistentDomain(forName: "ScriptConfigContainmentTests")
        defer { defaults.removePersistentDomain(forName: "ScriptConfigContainmentTests") }

        writeJSON(".dockyard.json", ["teardown": "true"])
        let approvedConfig = ScriptConfig.load(from: tmpDir.path)
        ScriptTrustStore.trust(projectDirectory: tmpDir.path, config: approvedConfig, defaults: defaults)
        try FileManager.default.removeItem(at: tmpDir.appendingPathComponent(".dockyard.json"))

        let outsideDirectory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outsideDirectory) }
        let marker = outsideDirectory.appendingPathComponent("teardown-ran")
        let outsideConfig = outsideDirectory.appendingPathComponent("outside.json")
        writeJSON(at: outsideConfig, ["teardown": "touch '\(marker.path)'"])
        try FileManager.default.createSymbolicLink(
            at: tmpDir.appendingPathComponent(".dockyard.json"),
            withDestinationURL: outsideConfig
        )

        ScriptConfig.runTeardown(in: tmpDir.path, projectDirectory: tmpDir.path, defaults: defaults)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: - Helpers

    func testRunTeardownSkipsUntrustedScripts() {
        let marker = tmpDir.appendingPathComponent("teardown-ran")
        writeJSON(".dockyard.json", ["teardown": "touch '\(marker.path)'"])

        let defaults = UserDefaults(suiteName: "ScriptConfigTeardownTests")!
        defaults.removePersistentDomain(forName: "ScriptConfigTeardownTests")
        defer { defaults.removePersistentDomain(forName: "ScriptConfigTeardownTests") }

        ScriptConfig.runTeardown(in: tmpDir.path, projectDirectory: tmpDir.path, defaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "untrusted teardown must not run")

        let config = ScriptConfig.load(from: tmpDir.path)
        ScriptTrustStore.trust(projectDirectory: tmpDir.path, config: config, defaults: defaults)
        ScriptConfig.runTeardown(in: tmpDir.path, projectDirectory: tmpDir.path, defaults: defaults)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), "trusted teardown must run")
    }

    private func writeJSON(_ name: String, _ dict: [String: Any]) {
        writeJSON(at: tmpDir.appendingPathComponent(name), dict)
    }

    private func writeJSON(at url: URL, _ dict: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: dict)
        FileManager.default.createFile(atPath: url.path, contents: data)
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
