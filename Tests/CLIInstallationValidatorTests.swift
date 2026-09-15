// ABOUTME: Tests bounded validation of the installed Dockyard CLI launcher.
// ABOUTME: Rejects oversized, linked, non-regular, non-executable, and unrelated candidates.

@testable import Dockyard
import XCTest

final class CLIInstallationValidatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-cli-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    func testExecutableLauncherAtByteCeilingValidates() throws {
        let launcher = root.appendingPathComponent("dy")
        let data = launcherData(byteCount: CLIInstallationValidator.maximumScriptBytes)
        try write(data, to: launcher, permissions: 0o755)

        XCTAssertTrue(CLIInstallationValidator.isValidLauncher(atPath: launcher.path))
        XCTAssertEqual(try Data(contentsOf: launcher), data)
    }

    func testOversizedLauncherIsRejectedWithoutMutation() throws {
        let launcher = root.appendingPathComponent("dy")
        let data = launcherData(byteCount: CLIInstallationValidator.maximumScriptBytes + 1)
        try write(data, to: launcher, permissions: 0o755)

        XCTAssertFalse(CLIInstallationValidator.isValidLauncher(atPath: launcher.path))
        XCTAssertEqual(try Data(contentsOf: launcher), data)
    }

    func testSymbolicLinkToValidLauncherIsRejected() throws {
        let target = root.appendingPathComponent("target")
        let link = root.appendingPathComponent("dy")
        try write(launcherData(), to: target, permissions: 0o755)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertFalse(CLIInstallationValidator.isValidLauncher(atPath: link.path))
    }

    func testDirectoryCandidateIsRejected() throws {
        let candidate = root.appendingPathComponent("dy", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)

        XCTAssertFalse(CLIInstallationValidator.isValidLauncher(atPath: candidate.path))
    }

    func testNonExecutableLauncherIsRejected() throws {
        let launcher = root.appendingPathComponent("dy")
        try write(launcherData(), to: launcher, permissions: 0o644)

        XCTAssertFalse(CLIInstallationValidator.isValidLauncher(atPath: launcher.path))
    }

    func testExecutableWithoutDockyardSchemeIsRejected() throws {
        let launcher = root.appendingPathComponent("dy")
        try write(Data("#!/bin/bash\nopen https://example.com\n".utf8), to: launcher, permissions: 0o755)

        XCTAssertFalse(CLIInstallationValidator.isValidLauncher(atPath: launcher.path))
    }

    private func launcherData(byteCount: Int? = nil) -> Data {
        var data = Data("#!/bin/bash\nopen \(AppConstants.urlScheme)://$PWD\n".utf8)
        if let byteCount {
            XCTAssertLessThan(data.count, byteCount)
            data.append(Data(repeating: 0x20, count: byteCount - data.count))
        }
        return data
    }

    private func write(_ data: Data, to url: URL, permissions: Int) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }
}
