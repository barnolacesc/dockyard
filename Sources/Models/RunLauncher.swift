// ABOUTME: Resolves the bundled dy-run helper and builds wrapped run-script commands.
// ABOUTME: Keeps Environment tab command assembly small and consistent across tmux modes.

import Darwin
import Foundation
import os

private let logger = Logger(subsystem: "dockyard", category: "run-launcher")

enum ProjectEnvironmentAccess {
    static func containedFileURL(
        _ relativePath: String,
        projectDirectory: String,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let candidateURL = containedURL(relativePath, projectDirectory: projectDirectory) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }

        return candidateURL
    }

    static func containedDirectoryURL(
        _ relativePath: String,
        projectDirectory: String,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let candidateURL = containedURL(relativePath, projectDirectory: projectDirectory) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }

        return candidateURL
    }

    private static func containedURL(_ relativePath: String, projectDirectory: String) -> URL? {
        guard !relativePath.isEmpty,
              !(relativePath as NSString).isAbsolutePath
        else { return nil }

        let projectURL = URL(fileURLWithPath: projectDirectory, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidateURL = URL(fileURLWithPath: projectDirectory, isDirectory: true)
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let projectComponents = projectURL.pathComponents
        let candidateComponents = candidateURL.pathComponents

        guard candidateComponents.count > projectComponents.count,
              candidateComponents.prefix(projectComponents.count).elementsEqual(projectComponents)
        else { return nil }

        return candidateURL
    }
}

enum RunLauncher {
    static let maximumEnvironmentFileBytes = 64 * 1024

    static func executableURL(bundle: Bundle = .main) -> URL? {
        let helperURL = bundle.bundleURL.appendingPathComponent("Contents/Helpers/dy-run")
        if FileManager.default.isExecutableFile(atPath: helperURL.path) {
            return helperURL
        }

        if let executableURL = bundle.executableURL {
            let siblingURL = executableURL.deletingLastPathComponent().appendingPathComponent("dy-run")
            if FileManager.default.isExecutableFile(atPath: siblingURL.path) {
                return siblingURL
            }
        }

        logger.warning("dy-run helper not found, port detection will be unavailable")
        return nil
    }
static func wrapWithVenv(_ script: String, projectDirectory: String) -> String {
    for candidate in ["venv/bin/activate", ".venv/bin/activate"] {
        if let activationURL = ProjectEnvironmentAccess.containedFileURL(
            candidate,
            projectDirectory: projectDirectory
        ) {
            return "source \(CommandBuilder.shellQuote(activationURL.path)) && \(script)"
        }
    }
    return script
}

static func inferExpectedPort(runCommand: String, projectDirectory: String) -> Int? {
    if let envString = boundedEnvironmentContents(projectDirectory: projectDirectory) {
        let lines = envString.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("PORT=") {
                let valStr = trimmed.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let port = Int(valStr) {
                    return port
                }
            }
        }
    }

    let portPattern = "(?:--port\\s+|-p\\s+|--port=)(\\d+)"
    if let regex = try? NSRegularExpression(pattern: portPattern),
       let match = regex.firstMatch(in: runCommand, range: NSRange(runCommand.startIndex..., in: runCommand)) {
        if let range = Range(match.range(at: 1), in: runCommand) {
            return Int(runCommand[range])
        }
    }

    let envVarPattern = "\\bPORT=(\\d+)"
    if let regex = try? NSRegularExpression(pattern: envVarPattern),
       let match = regex.firstMatch(in: runCommand, range: NSRange(runCommand.startIndex..., in: runCommand)) {
        if let range = Range(match.range(at: 1), in: runCommand) {
            return Int(runCommand[range])
        }
    }

    return nil
}

private static func boundedEnvironmentContents(projectDirectory: String) -> String? {
    guard let envURL = ProjectEnvironmentAccess.containedFileURL(
        ".env",
        projectDirectory: projectDirectory
    ) else { return nil }

    let descriptor = open(envURL.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { return nil }
    let fileHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? fileHandle.close() }

    var fileStatus = stat()
    guard fstat(descriptor, &fileStatus) == 0,
          (fileStatus.st_mode & S_IFMT) == S_IFREG,
          fileStatus.st_size <= off_t(maximumEnvironmentFileBytes),
          let data = try? fileHandle.read(upToCount: maximumEnvironmentFileBytes + 1),
          data.count <= maximumEnvironmentFileBytes
    else { return nil }

    return String(data: data, encoding: .utf8)
}
}

func runScriptCommand(script: String, workstreamID: UUID, launcherPath: String, expectedPort: Int? = nil, shell: String = CommandBuilder.userShell) -> String {
let workstream = workstreamID.uuidString.lowercased()
let quotedLauncher = CommandBuilder.shellQuote(launcherPath)
let quotedScript = CommandBuilder.shellQuote(script, forShell: shell)
var cmd = "\(quotedLauncher) --workstream-id \(workstream)"
if let expectedPort {
    cmd += " --expected-port \(expectedPort)"
}
cmd += " -- \(shell) -lic \(quotedScript)"
return cmd
}
