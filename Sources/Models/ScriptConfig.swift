// ABOUTME: Loads setup/run/teardown script configuration from project config files.
// ABOUTME: Resolves from .dockyard.json, .emdash.json, conductor.json, or .superset/config.json.

import Foundation
import os

private let logger = Logger(subsystem: "dockyard", category: "script-config")

struct ScriptConfig {
    /// Script configuration contains only a handful of command strings. Keep
    /// reads bounded well above normal use so repository files cannot cause an
    /// unbounded allocation before JSON parsing.
    static let maximumConfigFileBytes = 256 * 1024

    let setup: String?
    let run: String?
    let teardown: String?
    let expectedPort: Int?
    let source: String?
    let loadError: String?

    static let empty = ScriptConfig(setup: nil, run: nil, teardown: nil, expectedPort: nil, source: nil, loadError: nil)

    /// Load script config for a project directory.
    /// Checks .dockyard.json first, then .emdash.json, conductor.json, then .superset/config.json.
    static func load(from directory: String, fallbackDirectory: String? = nil) -> ScriptConfig {
        let directories = [directory] + (fallbackDirectory != nil ? [fallbackDirectory!] : [])
        
        for dirPath in directories {
            let dir = URL(fileURLWithPath: dirPath)
            let candidates: [(url: URL, source: String, loader: (String) throws -> ScriptConfig)] = [
                (dir.appendingPathComponent(".dockyard.json"), ".dockyard.json", loadDockyard),
                (dir.appendingPathComponent(".emdash.json"), ".emdash.json", loadEmdash),
                (dir.appendingPathComponent("conductor.json"), "conductor.json", loadConductor),
                (dir.appendingPathComponent(".superset/config.json"), ".superset/config.json", loadSuperset),
            ]

            for candidate in candidates {
                guard FileManager.default.fileExists(atPath: candidate.url.path) else { continue }
                do {
                    let resolvedPath = try resolvedConfigPath(candidate.url, within: dir)
                    return try candidate.loader(resolvedPath)
                } catch {
                    logger.error("Failed to load \(candidate.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return ScriptConfig(setup: nil, run: nil, teardown: nil, expectedPort: nil, source: candidate.source, loadError: error.localizedDescription)
                }
            }
        }

        return .empty
    }

    var hasAnyScript: Bool {
        setup != nil || run != nil || teardown != nil
    }

    /// Run the teardown script synchronously in the given directory.
    /// Scripts the user never approved (see ScriptTrustStore) are skipped.
    static func runTeardown(in directory: String, projectDirectory: String, defaults: UserDefaults = .standard) {
        let config = load(from: directory, fallbackDirectory: projectDirectory)
        guard let teardown = config.teardown else { return }
        guard ScriptTrustStore.isTrusted(projectDirectory: projectDirectory, config: config, defaults: defaults) else {
            logger.notice("Skipping teardown for \(directory, privacy: .public): scripts not approved")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandBuilder.userShell)
        process.arguments = ["-lic", teardown]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Loader

    enum LoadError: LocalizedError {
        case unreadable(String)
        case invalidJSON(String)
        case outsideProjectDirectory

        var errorDescription: String? {
            switch self {
            case let .unreadable(path): return "Cannot read \(path)"
            case let .invalidJSON(detail): return "Invalid JSON: \(detail)"
            case .outsideProjectDirectory:
                return NSLocalizedString("Script configuration must stay inside the project directory.", comment: "")
            }
        }
    }

    /// { "setup": "cmd", "run": "cmd", "teardown": "cmd" }
    private static func loadDockyard(_ path: String) throws -> ScriptConfig {
        let dict = try loadJSON(path)
        let setup = dict["setup"] as? String
        let run = dict["run"] as? String
        let teardown = dict["teardown"] as? String
        let expectedPort = dict["expectedPort"] as? Int
        guard setup != nil || run != nil || teardown != nil || expectedPort != nil else {
            return .empty
        }
        return ScriptConfig(setup: nonEmpty(setup), run: nonEmpty(run), teardown: nonEmpty(teardown), expectedPort: expectedPort, source: ".dockyard.json", loadError: nil)
    }

    /// .emdash.json: { "scripts": { "setup": "cmd", "run": "cmd", "teardown": "cmd" } }
    private static func loadEmdash(_ path: String) throws -> ScriptConfig {
        let dict = try loadJSON(path)
        guard let scripts = dict["scripts"] as? [String: Any] else { return .empty }
        let setup = scripts["setup"] as? String
        let run = scripts["run"] as? String
        let teardown = scripts["teardown"] as? String
        guard setup != nil || run != nil || teardown != nil else { return .empty }
        return ScriptConfig(setup: nonEmpty(setup), run: nonEmpty(run), teardown: nonEmpty(teardown), expectedPort: nil, source: ".emdash.json", loadError: nil)
    }

    /// conductor.json: { "scripts": { "setup": "cmd", "run": "cmd", "archive": "cmd" } }
    private static func loadConductor(_ path: String) throws -> ScriptConfig {
        let dict = try loadJSON(path)
        guard let scripts = dict["scripts"] as? [String: Any] else { return .empty }
        let setup = scripts["setup"] as? String
        let run = scripts["run"] as? String
        let teardown = scripts["archive"] as? String
        guard setup != nil || run != nil || teardown != nil else { return .empty }
        return ScriptConfig(setup: nonEmpty(setup), run: nonEmpty(run), teardown: nonEmpty(teardown), expectedPort: nil, source: "conductor.json", loadError: nil)
    }

    /// .superset/config.json: { "setup": ["cmd1", "cmd2"], "run": ["cmd"], "teardown": ["cmd"] }
    private static func loadSuperset(_ path: String) throws -> ScriptConfig {
        let dict = try loadJSON(path)
        let setup = joinCommands(dict["setup"])
        let run = joinCommands(dict["run"])
        let teardown = joinCommands(dict["teardown"])
        guard setup != nil || run != nil || teardown != nil else { return .empty }
        return ScriptConfig(setup: setup, run: run, teardown: teardown, expectedPort: nil, source: ".superset/config.json", loadError: nil)
    }

    // MARK: - Helpers

    /// Join a string array into a single command with &&, or return a plain string.
    private static func joinCommands(_ value: Any?) -> String? {
        if let array = value as? [String] {
            let joined = array.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " && ")
            return nonEmpty(joined)
        }
        if let str = value as? String {
            return nonEmpty(str)
        }
        return nil
    }

    private static func loadJSON(_ path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            throw LoadError.unreadable(path)
        }
        defer { try? handle.close() }

        var data = Data()
        do {
            while data.count <= maximumConfigFileBytes {
                let remaining = maximumConfigFileBytes + 1 - data.count
                guard remaining > 0,
                      let chunk = try handle.read(upToCount: min(64 * 1024, remaining)),
                      !chunk.isEmpty
                else {
                    break
                }
                data.append(chunk)
            }
        } catch {
            throw LoadError.unreadable(path)
        }

        guard data.count <= maximumConfigFileBytes else {
            throw LoadError.unreadable(path)
        }

        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw LoadError.invalidJSON("expected object, got \(type(of: obj))")
        }
        return dict
    }

    /// Resolve both paths before parsing so a config file or ancestor symlink
    /// cannot redirect script loading outside the directory it configures.
    private static func resolvedConfigPath(_ candidate: URL, within directory: URL) throws -> String {
        let resolvedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let directoryComponents = resolvedDirectory.pathComponents
        let candidateComponents = resolvedCandidate.pathComponents

        guard candidateComponents.count > directoryComponents.count,
              Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
        else {
            throw LoadError.outsideProjectDirectory
        }

        return resolvedCandidate.path
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }
}
