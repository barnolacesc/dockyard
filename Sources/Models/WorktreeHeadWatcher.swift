// ABOUTME: Watches each worktree's git HEAD directory for changes (e.g. `git branch -m`)
// ABOUTME: and fires a callback so the UI can resync branch names instantly, not on a poll.

import Foundation

/// Watches the per-worktree git directory (the directory containing `HEAD`) for every
/// registered worktree path. When HEAD changes — as it does on `git branch -m` of the
/// current branch — the `onChange` callback fires (debounced) with that worktree path so
/// the app can refresh its branch name immediately rather than waiting for the periodic
/// poll. Mirrors the directory-watching pattern used by `AgentStateStore`.
final class WorktreeHeadWatcher: @unchecked Sendable {
    private struct Watch {
        let source: DispatchSourceFileSystemObject
    }

    private let queue = DispatchQueue(label: "dockyard.worktree-head-watcher")
    private let onChange: @Sendable (String) -> Void
    private let debounce: DispatchTimeInterval

    /// worktree path -> active watch (mutated only on `queue`)
    private var watches: [String: Watch] = [:]
    /// worktree path -> pending debounced notify (mutated only on `queue`)
    private var pending: [String: DispatchWorkItem] = [:]

    init(debounce: DispatchTimeInterval = .milliseconds(200), onChange: @escaping @Sendable (String) -> Void) {
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        for watch in watches.values { watch.source.cancel() }
    }

    /// Reconcile the set of watched worktree paths to exactly `paths`: attach watchers for
    /// new paths, cancel watchers for paths no longer present. Safe to call repeatedly.
    func sync(paths: Set<String>) {
        queue.async { [weak self] in
            guard let self else { return }
            for (path, watch) in self.watches where !paths.contains(path) {
                watch.source.cancel()
                self.watches.removeValue(forKey: path)
                self.pending.removeValue(forKey: path)?.cancel()
            }
            for path in paths where self.watches[path] == nil {
                self.attach(path)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            for watch in self.watches.values { watch.source.cancel() }
            self.watches.removeAll()
            for work in self.pending.values { work.cancel() }
            self.pending.removeAll()
        }
    }

    /// Must run on `queue`.
    private func attach(_ worktreePath: String) {
        guard let gitDir = Self.headDirectory(forWorktree: worktreePath) else { return }
        let descriptor = open(gitDir, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleNotify(worktreePath)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        watches[worktreePath] = Watch(source: source)
        source.resume()
    }

    /// Must run on `queue`. Coalesces bursts of filesystem events per worktree path.
    private func scheduleNotify(_ worktreePath: String) {
        pending[worktreePath]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange(worktreePath)
        }
        pending[worktreePath] = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    /// Resolve the directory that contains a worktree's `HEAD` file. For a linked worktree,
    /// `.git` is a file pointing at the per-worktree git directory (`gitdir: <path>`); for a
    /// normal repository it is the `.git` directory itself. Returns nil for non-git paths.
    static func headDirectory(forWorktree path: String) -> String? {
        let gitEntry = URL(fileURLWithPath: path).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitEntry.path, isDirectory: &isDir) else {
            return nil
        }
        if isDir.boolValue {
            return gitEntry.path
        }
        guard let contents = try? String(contentsOf: gitEntry, encoding: .utf8) else { return nil }
        for rawLine in contents.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("gitdir:") {
                let dir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                return dir.isEmpty ? nil : dir
            }
        }
        return nil
    }
}
