// ABOUTME: Tests atomic state-file writes and their local privacy permissions.
// ABOUTME: Covers first writes, replacements, permission repair, and temp-file cleanup.

@testable import Dockyard
import XCTest

final class FilePersistenceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-file-persistence-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testFirstWriteCreatesPrivateDirectoryAndFile() throws {
        let directory = root.appendingPathComponent("state", isDirectory: true)
        let file = directory.appendingPathComponent("snapshot.json")

        try FilePersistence.writeAtomically(Data("first".utf8), to: file)

        XCTAssertEqual(try Data(contentsOf: file), Data("first".utf8))
        XCTAssertEqual(try permissions(of: directory), 0o700)
        XCTAssertEqual(try permissions(of: file), 0o600)
    }

    func testReplacementRepairsExistingDirectoryAndLeavesNoTemporaryFile() throws {
        let directory = root.appendingPathComponent("state", isDirectory: true)
        let file = directory.appendingPathComponent("snapshot.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try Data("old".utf8).write(to: file)

        try FilePersistence.writeAtomically(Data("replacement".utf8), to: file)

        XCTAssertEqual(try Data(contentsOf: file), Data("replacement".utf8))
        XCTAssertEqual(try permissions(of: directory), 0o700)
        XCTAssertEqual(try permissions(of: file), 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["snapshot.json"])
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}
