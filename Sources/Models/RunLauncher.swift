// ABOUTME: Resolves the bundled dy-run helper and builds wrapped run-script commands.
// ABOUTME: Keeps Environment tab command assembly small and consistent across tmux modes.

import Foundation
import os

private let logger = Logger(subsystem: "dockyard", category: "run-launcher")

enum RunLauncher {
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
}

func runScriptCommand(script: String, workstreamID: UUID, launcherPath: String, shell: String = CommandBuilder.userShell) -> String {
    let workstream = workstreamID.uuidString.lowercased()
    let quotedLauncher = CommandBuilder.shellQuote(launcherPath)
    let quotedScript = CommandBuilder.shellQuote(script, forShell: shell)
    return "\(quotedLauncher) --workstream-id \(workstream) -- \(shell) -lic \(quotedScript)"
}
