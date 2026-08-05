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
        let id: UUID
        let source: DispatchSourceFileSystemObject
    }

    private struct Reattachment {
        let id: UUID
        let work: DispatchWorkItem
    }

    private let queue = DispatchQueue(label: "dockyard.worktree-head-watcher")
    private let onChange: @Sendable (String) -> Void
    private let debounce: DispatchTimeInterval
    private let reattachDelay: DispatchTimeInterval
    private let maximumReattachAttempts = 20

    /// Worktree paths requested by the latest `sync` call (mutated only on `queue`).
    private var desiredPaths: Set<String> = []
    /// worktree path -> active watch (mutated only on `queue`)
    private var watches: [String: Watch] = [:]
    /// worktree path -> pending debounced notify (mutated only on `queue`)
    private var pending: [String: DispatchWorkItem] = [:]
    /// worktree path -> pending replacement-descriptor attempt (mutated only on `queue`)
    private var reattachments: [String: Reattachment] = [:]

    init(
        debounce: DispatchTimeInterval = .milliseconds(200),
        reattachDelay: DispatchTimeInterval = .milliseconds(100),
        onChange: @escaping @Sendable (String) -> Void
    ) {
        self.debounce = debounce
        self.reattachDelay = reattachDelay
        self.onChange = onChange
    }

    deinit {
        for watch in watches.values { watch.source.cancel() }
        for reattachment in reattachments.values { reattachment.work.cancel() }
        for work in pending.values { work.cancel() }
    }

    /// Reconcile the set of watched worktree paths to exactly `paths`: attach watchers for
    /// new paths, cancel watchers for paths no longer present. Safe to call repeatedly.
    func sync(paths: Set<String>) {
        queue.async { [weak self] in
            guard let self else { return }
            self.desiredPaths = paths
            for path in Array(self.watches.keys) where !paths.contains(path) {
                self.watches.removeValue(forKey: path)?.source.cancel()
                self.pending.removeValue(forKey: path)?.cancel()
                self.cancelReattachment(for: path)
            }
            for path in Array(self.reattachments.keys) where !paths.contains(path) {
                self.cancelReattachment(for: path)
            }
            for path in paths where self.watches[path] == nil {
                if !self.attach(path), self.reattachments[path] == nil {
                    self.scheduleReattachment(for: path, attempt: 1)
                }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.desiredPaths.removeAll()
            for watch in self.watches.values { watch.source.cancel() }
            self.watches.removeAll()
            for work in self.pending.values { work.cancel() }
            self.pending.removeAll()
            for reattachment in self.reattachments.values { reattachment.work.cancel() }
            self.reattachments.removeAll()
        }
    }

    /// Must run on `queue`. Returns false when git metadata is temporarily unavailable.
    @discardableResult
    private func attach(_ worktreePath: String) -> Bool {
        guard desiredPaths.contains(worktreePath) else { return false }
        guard let gitDir = Self.headDirectory(forWorktree: worktreePath) else { return false }
        let descriptor = open(gitDir, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let watchID = UUID()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleEvent(for: worktreePath, watchID: watchID)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        watches[worktreePath] = Watch(id: watchID, source: source)
        cancelReattachment(for: worktreePath)
        source.resume()
        return true
    }

    /// Must run on `queue`. Rename/delete invalidates the descriptor even if the path is
    /// immediately recreated, so replace it instead of waiting for the periodic sync.
    private func handleEvent(for worktreePath: String, watchID: UUID) {
        guard let watch = watches[worktreePath], watch.id == watchID else { return }
        let event = watch.source.data
        scheduleNotify(worktreePath)

        guard event.contains(.rename) || event.contains(.delete) else { return }
        watches.removeValue(forKey: worktreePath)
        watch.source.cancel()
        scheduleReattachment(for: worktreePath, attempt: 1)
    }

    /// Must run on `queue`. Git can replace metadata in multiple filesystem operations, so
    /// retry briefly without ever creating or mutating the repository metadata ourselves.
    private func scheduleReattachment(for worktreePath: String, attempt: Int) {
        guard desiredPaths.contains(worktreePath), watches[worktreePath] == nil else { return }
        guard attempt <= maximumReattachAttempts else { return }

        cancelReattachment(for: worktreePath)
        let reattachmentID = UUID()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.reattachments[worktreePath]?.id == reattachmentID
            else { return }
            self.reattachments.removeValue(forKey: worktreePath)
            guard self.desiredPaths.contains(worktreePath), self.watches[worktreePath] == nil else { return }
            if !self.attach(worktreePath) {
                self.scheduleReattachment(for: worktreePath, attempt: attempt + 1)
            }
        }
        reattachments[worktreePath] = Reattachment(id: reattachmentID, work: work)
        queue.asyncAfter(deadline: .now() + reattachDelay, execute: work)
    }

    /// Must run on `queue`.
    private func cancelReattachment(for worktreePath: String) {
        reattachments.removeValue(forKey: worktreePath)?.work.cancel()
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
