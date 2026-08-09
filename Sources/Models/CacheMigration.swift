// ABOUTME: Moves run-state and tmux.conf from ~/.config/dockyard/ to ~/Library/Caches/dockyard/.
// ABOUTME: Runs once on launch; removes the old config directory if empty afterward.

import Foundation

enum CacheMigration {
    static func migrateIfNeeded() {
        migrateIfNeeded(
            from: AppConstants.configDirectory,
            to: AppConstants.cacheDirectory
        )
    }

    static func migrateIfNeeded(
        from oldBase: URL,
        to newBase: URL,
        fileManager fm: FileManager = .default
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
        removeDirectoryIfEmpty(oldBase, fileManager: fm)
    }

    private static func moveIfExists(from source: URL, to destination: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: source.path) else { return }
        // Canonical cache state may be newer than the legacy entry. Keep both
        // when there is a conflict so a fallible migration cannot destroy data.
        guard !fm.fileExists(atPath: destination.path) else { return }
        try? fm.moveItem(at: source, to: destination)
    }

    private static func removeDirectoryIfEmpty(_ url: URL, fileManager fm: FileManager) {
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else { return }
        let visible = contents.filter { !$0.hasPrefix(".") }
        if visible.isEmpty {
            try? fm.removeItem(at: url)
        }
    }
}
