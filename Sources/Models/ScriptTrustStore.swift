// ABOUTME: Tracks which projects' setup/run/teardown scripts the user has approved.
// ABOUTME: Fingerprints script content so any change requires re-approval.

import CryptoKit
import Foundation

enum ScriptTrustStore {
    private static let userDefaultsKey = "dockyard.trustedScripts"

    /// A config with no scripts needs no approval.
    static func isTrusted(projectDirectory: String, config: ScriptConfig, defaults: UserDefaults = .standard) -> Bool {
        guard config.hasAnyScript else { return true }
        let stored = defaults.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
        return stored[projectDirectory] == fingerprint(setup: config.setup, run: config.run, teardown: config.teardown)
    }

    static func trust(projectDirectory: String, config: ScriptConfig, defaults: UserDefaults = .standard) {
        trust(projectDirectory: projectDirectory, setup: config.setup, run: config.run, teardown: config.teardown, defaults: defaults)
    }

    static func trust(projectDirectory: String, setup: String?, run: String?, teardown: String?, defaults: UserDefaults = .standard) {
        var stored = defaults.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
        stored[projectDirectory] = fingerprint(setup: setup, run: run, teardown: teardown)
        defaults.set(stored, forKey: userDefaultsKey)
    }

    /// Length-prefixed framing keeps nil/empty/shifted fields from colliding.
    private static func fingerprint(setup: String?, run: String?, teardown: String?) -> String {
        let framed = [("setup", setup), ("run", run), ("teardown", teardown)].map { name, value -> String in
            guard let value else { return "\(name):nil;" }
            return "\(name):\(value.utf8.count):\(value);"
        }.joined()
        let digest = SHA256.hash(data: Data(framed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
