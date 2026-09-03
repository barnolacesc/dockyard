// ABOUTME: Tests bounded reads of worktree task-description metadata.
// ABOUTME: Rejects oversized and non-regular candidates while preserving normal descriptions.

@testable import Dockyard
import Foundation
import XCTest

final class EnvironmentDescriptionTests: XCTestCase {
    private var fixtureDirectory: URL!
    private var descriptionURL: URL!

    override func setUpWithError() throws {
        fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-description-tests-\(UUID().uuidString)", isDirectory: true)
        let stateDirectory = fixtureDirectory.appendingPathComponent(".dockyard-state", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        descriptionURL = stateDirectory.appendingPathComponent("description")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    func testReadsAndTrimsOrdinaryDescription() throws {
        try Data("  Implement safer metadata reads\r\n".utf8).write(to: descriptionURL)

        XCTAssertEqual(
            TaskDescriptionReader.read(for: fixtureDirectory.path),
            "Implement safer metadata reads"
        )
    }

    func testReadsDescriptionAtMaximumSize() throws {
        let data = Data(repeating: 0x61, count: TaskDescriptionReader.maximumDescriptionBytes)
        try data.write(to: descriptionURL)

        let description = try XCTUnwrap(TaskDescriptionReader.read(from: descriptionURL))

        XCTAssertEqual(description.utf8.count, TaskDescriptionReader.maximumDescriptionBytes)
    }

    func testRejectsOversizedDescription() throws {
        let data = Data(
            repeating: 0x61,
            count: TaskDescriptionReader.maximumDescriptionBytes + 1
        )
        try data.write(to: descriptionURL)

        XCTAssertNil(TaskDescriptionReader.read(from: descriptionURL))
    }

    func testRejectsSymbolicLinkDescription() throws {
        let target = fixtureDirectory.appendingPathComponent("outside-description")
        try Data("Do not follow me".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: descriptionURL, withDestinationURL: target)

        XCTAssertNil(TaskDescriptionReader.read(from: descriptionURL))
    }

    func testRejectsDirectoryDescription() throws {
        try FileManager.default.createDirectory(at: descriptionURL, withIntermediateDirectories: false)

        XCTAssertNil(TaskDescriptionReader.read(from: descriptionURL))
    }

    func testRejectsInvalidUTF8Description() throws {
        try Data([0xFF, 0xFE]).write(to: descriptionURL)

        XCTAssertNil(TaskDescriptionReader.read(from: descriptionURL))
    }

    func testWhitespaceOnlyDescriptionRemainsEmpty() throws {
        try Data(" \t\r\n".utf8).write(to: descriptionURL)

        XCTAssertNil(TaskDescriptionReader.read(from: descriptionURL))
    }
}
