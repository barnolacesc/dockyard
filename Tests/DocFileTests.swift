// ABOUTME: Tests containment and compatibility for standard project-document previews.
// ABOUTME: Prevents README, CLAUDE, and AGENTS symlinks from reading outside a project.

@testable import Dockyard
import XCTest

final class DocFileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testLoadsRegularStandardDocument() throws {
        let project = try makeDirectory(named: "project")
        try writeDocument("# Project\n\nRegular documentation.", to: project.appendingPathComponent("README.md"))

        let documents = DocFile.loadFrom(directory: project.path)

        XCTAssertEqual(documents.map(\.name), ["README.md"])
        XCTAssertEqual(documents.first?.content, "# Project\n\nRegular documentation.")
    }

    func testLoadsStandardDocumentSymlinkResolvingInsideProject() throws {
        let project = try makeDirectory(named: "project")
        let docs = try makeDirectory(named: "project/docs")
        let target = docs.appendingPathComponent("project-readme.md")
        try writeDocument("# Project\n\nContained symlink target.", to: target)
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("README.md"),
            withDestinationURL: target
        )

        let documents = DocFile.loadFrom(directory: project.path)

        XCTAssertEqual(documents.map(\.name), ["README.md"])
        XCTAssertEqual(documents.first?.content, "# Project\n\nContained symlink target.")
    }

    func testRejectsStandardDocumentSymlinkResolvingOutsideProject() throws {
        let project = try makeDirectory(named: "project")
        let outside = root.appendingPathComponent("outside-readme.md")
        try writeDocument("# Private\n\nOutside project content.", to: outside)
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("README.md"),
            withDestinationURL: outside
        )

        XCTAssertTrue(DocFile.loadFrom(directory: project.path).isEmpty)
    }

    func testRejectsStandardDocumentWhoseTargetUsesEscapingAncestorSymlink() throws {
        let project = try makeDirectory(named: "project")
        let outsideDocs = try makeDirectory(named: "outside-docs")
        let outside = outsideDocs.appendingPathComponent("README.md")
        try writeDocument("# Private\n\nEscaped through ancestor.", to: outside)
        let linkedDocs = project.appendingPathComponent("linked-docs")
        try FileManager.default.createSymbolicLink(at: linkedDocs, withDestinationURL: outsideDocs)
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("README.md"),
            withDestinationURL: linkedDocs.appendingPathComponent("README.md")
        )

        XCTAssertTrue(DocFile.loadFrom(directory: project.path).isEmpty)
    }

    func testLoadsDocumentFromSymlinkedProjectRoot() throws {
        let realProject = try makeDirectory(named: "real-project")
        try writeDocument("# Project\n\nResolved project root.", to: realProject.appendingPathComponent("README.md"))
        let linkedProject = root.appendingPathComponent("linked-project")
        try FileManager.default.createSymbolicLink(at: linkedProject, withDestinationURL: realProject)

        let documents = DocFile.loadFrom(directory: linkedProject.path)

        XCTAssertEqual(documents.map(\.name), ["README.md"])
        XCTAssertEqual(documents.first?.content, "# Project\n\nResolved project root.")
    }

    func testKeepsMinimumLengthAndUTF8Requirements() throws {
        let project = try makeDirectory(named: "project")
        try writeDocument("short", to: project.appendingPathComponent("README.md"))
        try Data([0xFF, 0xFE] + Array(repeating: 0xFF, count: 18))
            .write(to: project.appendingPathComponent("AGENTS.md"))

        XCTAssertTrue(DocFile.loadFrom(directory: project.path).isEmpty)
    }

    private func makeDirectory(named relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeDocument(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
