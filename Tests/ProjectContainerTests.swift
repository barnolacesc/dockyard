// ABOUTME: Tests for ProjectContainerView and ProjectTab state.
// ABOUTME: Validates project tabs, terminal surface derivation, and script configuration.

@testable import Dockyard
import XCTest

final class ProjectContainerTests: XCTestCase {
    func testProjectTabEnumCases() {
        let tabs = ProjectTab.allCases
        XCTAssertEqual(tabs, [.overview, .terminal])
    }

    func testProjectTerminalDerivedUUIDIsDeterministic() {
        let projectID = UUID()
        let id1 = derivedUUID(from: projectID, salt: "project-root-terminal")
        let id2 = derivedUUID(from: projectID, salt: "project-root-terminal")
        XCTAssertEqual(id1, id2)

        let otherProjectID = UUID()
        let idOther = derivedUUID(from: otherProjectID, salt: "project-root-terminal")
        XCTAssertNotEqual(id1, idOther)
    }

    func testProjectScriptConfigDetectionAndWrite() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write package.json
        let pkgJSON = """
        {
          "scripts": {
            "build": "vite build",
            "dev": "vite",
            "clean": "rimraf dist"
          }
        }
        """
        try pkgJSON.write(to: tempDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let draft = StackDetector.detect(at: tempDir.path)
        XCTAssertFalse(draft.isEmpty)
        XCTAssertEqual(draft.run, "npm run dev")

        try DockyardConfigWriter.write(draft, to: tempDir.path)
        let loaded = ScriptConfig.load(from: tempDir.path)
        XCTAssertEqual(loaded.run, "npm run dev")
        XCTAssertEqual(loaded.source, ".dockyard.json")
    }
}
