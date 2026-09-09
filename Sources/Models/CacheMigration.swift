// ABOUTME: Moves run-state and tmux.conf from ~/.config/dockyard/ to ~/Library/Caches/dockyard/.
// ABOUTME: Runs once on launch; removes the old config directory if empty afterward.

import Foundation

enum CacheMigration {
    static let defaultDirectoryEntryInspectionLimit = 1_024

    enum DirectoryContents: Equatable {
        case empty
        case nonEmpty
        case inspectionLimitReached
    }

    static func migrateIfNeeded() {
        migrateIfNeeded(
            from: AppConstants.configDirectory,
            to: AppConstants.cacheDirectory
        )
    }

    static func migrateIfNeeded(
        from oldBase: URL,
        to newBase: URL,
        fileManager fm: FileManager = .default,
        directoryEntryInspectionLimit: Int = defaultDirectoryEntryInspectionLimit
    ) {
        try? fm.createDirectory(at: newBase, withIntermediateDirectories: true)

        // Migrate run-state directory
        let oldRunState = oldBase.appendingPathComponent("run-state", isDirectory: true)
        let newRunState = newBase.appendingPathComponent("run-state", isDirectory: true)
        moveIfExists(from: oldRunState, to: newRunState, fileManager: fm)

        // Migrate tmux.conf
        let oldTmux = oldBase.appendingPathComponent("tmux.conf")
        let newTmux = newBase.appendingPathComponent("tmux.conf")
        moveIfExists(from: oldTmux, to: newTmux, fileManager: fm)

        // Remove old config directory if empty
        removeDirectoryIfEmpty(
            oldBase,
            fileManager: fm,
            maximumEntriesToInspect: directoryEntryInspectionLimit
        )
    }

    private static func moveIfExists(from source: URL, to destination: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: source.path) else { return }
        // Canonical cache state may be newer than the legacy entry. Keep both
        // when there is a conflict so a fallible migration cannot destroy data.
        guard !fm.fileExists(atPath: destination.path) else { return }
        try? fm.moveItem(at: source, to: destination)
    }

    private static func removeDirectoryIfEmpty(
        _ url: URL,
        fileManager fm: FileManager,
        maximumEntriesToInspect: Int
    ) {
        var enumerationFailed = false
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else { return }

        let contents = classifyDirectoryContents(
            maximumEntriesToInspect: maximumEntriesToInspect
        ) {
            guard let entry = enumerator.nextObject() else { return nil }
            guard let entryURL = entry as? URL else {
                enumerationFailed = true
                return nil
            }
            return entryURL.lastPathComponent
        }

        guard !enumerationFailed, contents == .empty else { return }
        try? fm.removeItem(at: url)
    }

    static func classifyDirectoryContents(
        maximumEntriesToInspect: Int,
        nextEntry: () -> String?
    ) -> DirectoryContents {
        guard maximumEntriesToInspect > 0 else { return .inspectionLimitReached }

        for _ in 0 ..< maximumEntriesToInspect {
            guard let entry = nextEntry() else { return .empty }
            if !entry.hasPrefix(".") {
                return .nonEmpty
            }
        }

        return .inspectionLimitReached
    }
}
