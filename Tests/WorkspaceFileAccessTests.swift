// ABOUTME: Tests embedded-editor file access remains inside the selected worktree.
// ABOUTME: Covers traversal, prefix siblings, symlink escapes, and symlinked roots.

@testable import Dockyard
import Foundation
import XCTest

final class WorkspaceFileAccessTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var workspace: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-workspace-file-tests-\(UUID().uuidString)")
        workspace = temporaryDirectory.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testResolvesDescendantThroughSymlinkedWorkspaceRoot() throws {
        let nestedDirectory = workspace.appendingPathComponent("Sources", isDirectory: true)
        let file = nestedDirectory.appendingPathComponent("App.swift")
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let linkedWorkspace = temporaryDirectory.appendingPathComponent("workspace-link")
        try FileManager.default.createSymbolicLink(at: linkedWorkspace, withDestinationURL: workspace)

        let resolved = WorkspaceFileAccess.resolvedURL(
            for: "Sources/App.swift",
            rootPath: linkedWorkspace.path
        )

        XCTAssertEqual(resolved, file.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(
            try WorkspaceFileAccess.readEditorContent(
                at: "Sources/App.swift",
                rootPath: linkedWorkspace.path
            ),
            "content"
        )
    }

    func testRejectsAbsoluteTraversalAndPrefixSiblingPaths() throws {
        let sibling = temporaryDirectory.appendingPathComponent("workspace-backup", isDirectory: true)
        let secret = sibling.appendingPathComponent("secret.txt")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try "secret".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("prefix-sibling"),
            withDestinationURL: sibling
        )

        XCTAssertNil(WorkspaceFileAccess.resolvedURL(for: secret.path, rootPath: workspace.path))
        XCTAssertNil(
            WorkspaceFileAccess.resolvedURL(
                for: "../workspace-backup/secret.txt",
                rootPath: workspace.path
            )
        )
        XCTAssertNil(
            WorkspaceFileAccess.resolvedURL(
                for: "prefix-sibling/secret.txt",
                rootPath: workspace.path
            )
        )
        XCTAssertNil(WorkspaceFileAccess.resolvedURL(for: ".", rootPath: workspace.path))

        for path in [secret.path, "../workspace-backup/secret.txt", "."] {
            XCTAssertThrowsError(
                try WorkspaceFileAccess.readEditorContent(
                    at: path,
                    rootPath: workspace.path
                ),
                "Expected read rejection for \(path)"
            ) { error in
                XCTAssertEqual((error as? CocoaError)?.code, .fileReadNoPermission)
            }
        }
    }

    func testRejectsFileAndDirectorySymlinksOutsideWorkspace() throws {
        let outsideDirectory = temporaryDirectory.appendingPathComponent("outside", isDirectory: true)
        let outsideFile = outsideDirectory.appendingPathComponent("secret.txt")
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("external-directory"),
            withDestinationURL: outsideDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("external-file"),
            withDestinationURL: outsideFile
        )

        XCTAssertNil(
            WorkspaceFileAccess.resolvedURL(
                for: "external-directory/secret.txt",
                rootPath: workspace.path
            )
        )
        XCTAssertNil(WorkspaceFileAccess.resolvedURL(for: "external-file", rootPath: workspace.path))
    }

    func testWritesEditorContentOnlyToContainedRelativePath() throws {
        let sourceDirectory = workspace.appendingPathComponent("Sources", isDirectory: true)
        let file = sourceDirectory.appendingPathComponent("App.swift")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try "old".write(to: file, atomically: true, encoding: .utf8)

        try WorkspaceFileAccess.writeEditorContent(
            "new",
            to: "Sources/App.swift",
            rootPath: workspace.path
        )

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "new")
    }

    func testReadsRegularUTF8EditorContentAtMaximumSize() throws {
        let file = workspace.appendingPathComponent("large.swift")
        let data = Data(repeating: 0x61, count: WorkspaceFileAccess.maximumEditorFileBytes)
        try data.write(to: file)

        let content = try WorkspaceFileAccess.readEditorContent(
            at: "large.swift",
            rootPath: workspace.path
        )

        XCTAssertEqual(content.utf8.count, WorkspaceFileAccess.maximumEditorFileBytes)
        XCTAssertEqual(content.first, "a")
        XCTAssertEqual(content.last, "a")
    }

    func testRejectsOversizedEditorContent() throws {
        let file = workspace.appendingPathComponent("oversized.swift")
        let data = Data(
            repeating: 0x61,
            count: WorkspaceFileAccess.maximumEditorFileBytes + 1
        )
        try data.write(to: file)

        XCTAssertThrowsError(
            try WorkspaceFileAccess.readEditorContent(
                at: "oversized.swift",
                rootPath: workspace.path
            )
        ) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadTooLarge)
        }
    }

    func testRejectsSymbolicLinkEditorContent() throws {
        let target = workspace.appendingPathComponent("target.swift")
        let link = workspace.appendingPathComponent("linked.swift")
        try "content".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(
            try WorkspaceFileAccess.readEditorContent(
                at: "linked.swift",
                rootPath: workspace.path
            )
        ) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadNoPermission)
        }
    }

    func testRejectsNonRegularEditorContent() throws {
        let directory = workspace.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try WorkspaceFileAccess.readEditorContent(
                at: "Sources",
                rootPath: workspace.path
            )
        ) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadUnknown)
        }
    }

    func testRejectsUnsafeEditorWritePathsWithoutChangingOutsideFiles() throws {
        let sibling = temporaryDirectory.appendingPathComponent("workspace-backup", isDirectory: true)
        let siblingFile = sibling.appendingPathComponent("secret.txt")
        let outsideDirectory = temporaryDirectory.appendingPathComponent("outside", isDirectory: true)
        let outsideFile = outsideDirectory.appendingPathComponent("secret.txt")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try "sibling".write(to: siblingFile, atomically: true, encoding: .utf8)
        try "outside".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("external-directory"),
            withDestinationURL: outsideDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("external-file"),
            withDestinationURL: outsideFile
        )

        let unsafePaths = [
            siblingFile.path,
            "../workspace-backup/secret.txt",
            "external-directory/secret.txt",
            "external-file",
        ]

        for path in unsafePaths {
            XCTAssertThrowsError(
                try WorkspaceFileAccess.writeEditorContent(
                    "overwritten",
                    to: path,
                    rootPath: workspace.path
                ),
                "Expected write rejection for \(path)"
            ) { error in
                XCTAssertEqual((error as? CocoaError)?.code, .fileWriteNoPermission)
            }
        }

        XCTAssertEqual(try String(contentsOf: siblingFile, encoding: .utf8), "sibling")
        XCTAssertEqual(try String(contentsOf: outsideFile, encoding: .utf8), "outside")
    }

    func testFileTreeOmitsEscapingSymlinksAndKeepsContainedOnes() throws {
        let containedDirectory = workspace.appendingPathComponent("contained", isDirectory: true)
        let containedFile = containedDirectory.appendingPathComponent("visible.txt")
        let outsideDirectory = temporaryDirectory.appendingPathComponent("outside", isDirectory: true)
        let outsideFile = outsideDirectory.appendingPathComponent("secret.txt")
        try FileManager.default.createDirectory(at: containedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try "visible".write(to: containedFile, atomically: true, encoding: .utf8)
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("contained-link"),
            withDestinationURL: containedDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("external-directory"),
            withDestinationURL: outsideDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("external-file"),
            withDestinationURL: outsideFile
        )

        let tree = FileNode.buildShallowTree(rootPath: workspace.path)
        let names = Set(tree.map(\.name))

        XCTAssertTrue(names.contains("contained"))
        XCTAssertTrue(names.contains("contained-link"))
        XCTAssertFalse(names.contains("external-directory"))
        XCTAssertFalse(names.contains("external-file"))

        let linkedChildren = FileNode.loadChildren(
            atRelativePath: "contained-link",
            rootPath: workspace.path
        )
        XCTAssertEqual(linkedChildren.map(\.id), ["contained-link/visible.txt"])
        XCTAssertTrue(
            FileNode.loadChildren(
                atRelativePath: "external-directory",
                rootPath: workspace.path
            ).isEmpty
        )
    }
}
