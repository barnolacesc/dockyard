// ABOUTME: Tests bounded and project-contained expected-port inference for run scripts.
// ABOUTME: Covers regular .env files, escaping symlinks, non-files, size limits, and command fallbacks.

@testable import Dockyard
import Darwin
import XCTest

final class RunLauncherPortInferenceTests: XCTestCase {
    func testInfersExpectedPortFromContainedEnvironmentFile() throws {
        let projectDirectory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: projectDirectory) }
        try Data("PORT=7777\n".utf8).write(to: projectDirectory.appendingPathComponent(".env"))

        XCTAssertEqual(
            RunLauncher.inferExpectedPort(
                runCommand: "npm run start",
                projectDirectory: projectDirectory.path
            ),
            7777
        )
    }

    func testIgnoresEnvironmentSymlinkEscapingProject() throws {
        let fixtureDirectory = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        let projectDirectory = fixtureDirectory.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let outsideEnvironment = fixtureDirectory.appendingPathComponent("outside.env")
        try Data("PORT=7777\n".utf8).write(to: outsideEnvironment)
        try FileManager.default.createSymbolicLink(
            at: projectDirectory.appendingPathComponent(".env"),
            withDestinationURL: outsideEnvironment
        )

        XCTAssertEqual(
            RunLauncher.inferExpectedPort(
                runCommand: "next dev --port 4555",
                projectDirectory: projectDirectory.path
            ),
            4555
        )
    }

    func testIgnoresNonRegularEnvironmentCandidate() throws {
        let projectDirectory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: projectDirectory) }
        XCTAssertEqual(
            mkfifo(projectDirectory.appendingPathComponent(".env").path, S_IRUSR | S_IWUSR),
            0
        )

        XCTAssertEqual(
            RunLauncher.inferExpectedPort(
                runCommand: "PORT=4666 node server.js",
                projectDirectory: projectDirectory.path
            ),
            4666
        )
    }

    func testIgnoresOversizedEnvironmentFile() throws {
        let projectDirectory = try makeProjectDirectory()
        defer { try? FileManager.default.removeItem(at: projectDirectory) }
        var oversizedEnvironment = Data("PORT=7777\n".utf8)
        oversizedEnvironment.append(
            Data(
                repeating: 0x41,
                count: RunLauncher.maximumEnvironmentFileBytes - oversizedEnvironment.count + 1
            )
        )
        try oversizedEnvironment.write(to: projectDirectory.appendingPathComponent(".env"))

        XCTAssertEqual(
            RunLauncher.inferExpectedPort(
                runCommand: "uvicorn app:app -p 4777",
                projectDirectory: projectDirectory.path
            ),
            4777
        )
        XCTAssertEqual(oversizedEnvironment.count, RunLauncher.maximumEnvironmentFileBytes + 1)
    }

    private func makeProjectDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-run-launcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeFixtureDirectory() throws -> URL {
        try makeProjectDirectory()
    }
}
