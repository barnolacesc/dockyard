// ABOUTME: Tests safe migration of legacy run-state and tmux cache entries.
// ABOUTME: Ensures an existing canonical cache is never replaced by legacy data.

@testable import Dockyard
import XCTest

final class CacheMigrationTests: XCTestCase {
    private var root: URL!
    private var legacyBase: URL!
    private var canonicalBase: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-cache-migration-\(UUID().uuidString)", isDirectory: true)
        legacyBase = root.appendingPathComponent("legacy", isDirectory: true)
        canonicalBase = root.appendingPathComponent("canonical", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyBase, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testMovesLegacyEntriesWhenCanonicalEntriesAreMissing() throws {
        let legacyRunState = legacyBase.appendingPathComponent("run-state", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyRunState, withIntermediateDirectories: true)
        try Data("legacy state".utf8).write(
            to: legacyRunState.appendingPathComponent("workstream.json")
        )
        try Data("legacy tmux".utf8).write(
            to: legacyBase.appendingPathComponent("tmux.conf")
        )

        CacheMigration.migrateIfNeeded(from: legacyBase, to: canonicalBase)

        XCTAssertEqual(
            try Data(contentsOf: canonicalBase.appendingPathComponent("run-state/workstream.json")),
            Data("legacy state".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: canonicalBase.appendingPathComponent("tmux.conf")),
            Data("legacy tmux".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyBase.path))
    }

    func testPreservesCanonicalEntriesWhenLegacyEntriesAlsoExist() throws {
        let legacyRunState = legacyBase.appendingPathComponent("run-state", isDirectory: true)
        let canonicalRunState = canonicalBase.appendingPathComponent("run-state", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyRunState, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: canonicalRunState, withIntermediateDirectories: true)
        try Data("legacy state".utf8).write(
            to: legacyRunState.appendingPathComponent("workstream.json")
        )
        try Data("canonical state".utf8).write(
            to: canonicalRunState.appendingPathComponent("workstream.json")
        )
        try Data("legacy tmux".utf8).write(
            to: legacyBase.appendingPathComponent("tmux.conf")
        )
        try Data("canonical tmux".utf8).write(
            to: canonicalBase.appendingPathComponent("tmux.conf")
        )

        CacheMigration.migrateIfNeeded(from: legacyBase, to: canonicalBase)

        XCTAssertEqual(
            try Data(contentsOf: canonicalRunState.appendingPathComponent("workstream.json")),
            Data("canonical state".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: canonicalBase.appendingPathComponent("tmux.conf")),
            Data("canonical tmux".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: legacyRunState.appendingPathComponent("workstream.json")),
            Data("legacy state".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: legacyBase.appendingPathComponent("tmux.conf")),
            Data("legacy tmux".utf8)
        )
    }
}
