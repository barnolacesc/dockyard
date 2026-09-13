// ABOUTME: Pure logic deciding which What's New releases to present after an
// ABOUTME: update, based on the last seen version or a completed source update.

import Foundation

enum WhatsNewGate {
    static let lastSeenKey = "dockyard.lastSeenVersion"
    static let pendingSourceUpdateCommitKey = "dockyard.pendingSourceUpdateCommit"

    /// Releases to present, newest first. Empty on fresh installs (lastSeen nil),
    /// when nothing changed, or when the catalog has no matching releases.
    static func releasesToPresent(
        current: String,
        lastSeen: String?,
        catalog: [WhatsNewRelease],
        includeCurrentRelease: Bool = false
    ) -> [WhatsNewRelease] {
        if let lastSeen, lastSeen != current {
            let newerReleases = catalog.filter {
                isVersion($0.version, newerThan: lastSeen) && !isVersion($0.version, newerThan: current)
            }
            if !newerReleases.isEmpty { return newerReleases }
        }

        guard includeCurrentRelease else { return [] }
        return catalog.filter { $0.version == current }
    }

    static func sourceUpdateWasApplied(pendingCommit: String?, currentCommit: String) -> Bool {
        guard let pendingCommit, !pendingCommit.isEmpty else { return false }
        return pendingCommit != currentCommit
    }

    /// Numeric dot-component comparison ("0.10.0" > "0.9.0"). Non-numeric
    /// components count as 0; missing components count as 0.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let ac = components(a)
        let bc = components(b)
        for index in 0 ..< max(ac.count, bc.count) {
            let x = index < ac.count ? ac[index] : 0
            let y = index < bc.count ? bc[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }
}
