// ABOUTME: FileNode tree model with lazy directory loading (children loaded on expand).
// ABOUTME: DirectoryWatcher uses FSEventStream for real-time recursive file system monitoring.

import Foundation

// MARK: - Workspace File Access

enum WorkspaceFileAccess {
    /// Resolves a workspace-relative path after proving that its canonical
    /// destination remains below the canonical workspace root.
    static func resolvedURL(for relativePath: String, rootPath: String) -> URL? {
        guard !relativePath.isEmpty,
              !(relativePath as NSString).isAbsolutePath
        else { return nil }

        let components = (relativePath as NSString).pathComponents
        guard !components.contains("."), !components.contains("..") else { return nil }

        let rootURL = canonicalRootURL(for: rootPath)
        let candidateURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard isDescendant(candidateURL, of: rootURL) else { return nil }
        return candidateURL
    }

    static func canonicalRootURL(for rootPath: String) -> URL {
        URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    /// Writes editor content only after resolving a workspace-relative path
    /// through the same containment boundary used for editor reads.
    static func writeEditorContent(
        _ content: String,
        to relativePath: String,
        rootPath: String
    ) throws {
        guard let destinationURL = resolvedURL(for: relativePath, rootPath: rootPath) else {
            throw CocoaError(.fileWriteNoPermission)
        }

        try content.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    private static func isDescendant(_ candidateURL: URL, of rootURL: URL) -> Bool {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let candidateComponents = candidateURL.standardizedFileURL.pathComponents

        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}

// MARK: - FileNode

struct FileNode: Identifiable {
    let id: String // relative path from worktree root (empty string for root)
    let name: String // last path component
    let isDirectory: Bool
    var children: [FileNode]? // nil = not yet loaded (lazy), [] = loaded but empty

    /// Whether this directory's children have been loaded.
    var isLoaded: Bool {
        children != nil
    }

    /// Build a shallow tree (root level only). Directory children are nil (lazy).
    static func buildShallowTree(rootPath: String) -> [FileNode] {
        buildShallowChildren(
            at: WorkspaceFileAccess.canonicalRootURL(for: rootPath),
            relativePathPrefix: "",
            rootPath: rootPath
        )
    }

    /// Load immediate children of a single directory. Directories get children = nil (lazy).
    static func loadChildren(atRelativePath relativePath: String, rootPath: String) -> [FileNode] {
        let directoryURL: URL
        if relativePath.isEmpty {
            directoryURL = WorkspaceFileAccess.canonicalRootURL(for: rootPath)
        } else if let resolvedURL = WorkspaceFileAccess.resolvedURL(
            for: relativePath,
            rootPath: rootPath
        ) {
            directoryURL = resolvedURL
        } else {
            return []
        }

        return buildShallowChildren(
            at: directoryURL,
            relativePathPrefix: relativePath,
            rootPath: rootPath
        )
    }

    /// Insert loaded children at a specific path in the tree, returning the updated tree.
    static func insertChildren(_ children: [FileNode], atPath path: String, in nodes: [FileNode]) -> [FileNode] {
        nodes.map { node in
            if node.id == path, node.isDirectory {
                return FileNode(id: node.id, name: node.name, isDirectory: true, children: children)
            } else if node.isDirectory, let nodeChildren = node.children, path.hasPrefix(node.id + "/") {
                let updatedChildren = insertChildren(children, atPath: path, in: nodeChildren)
                return FileNode(id: node.id, name: node.name, isDirectory: true, children: updatedChildren)
            }
            return node
        }
    }

    /// Ensure all ancestor directories for a file path are loaded. Returns the updated tree.
    static func ensureAncestorsLoaded(for filePath: String, in nodes: [FileNode], rootPath: String) -> [FileNode] {
        let components = filePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return nodes }

        var result = nodes
        var current = ""
        for component in components.dropLast() {
            current = current.isEmpty ? component : current + "/" + component
            if let node = findNode(atPath: current, in: result), node.isDirectory, !node.isLoaded {
                let children = loadChildren(atRelativePath: current, rootPath: rootPath)
                result = insertChildren(children, atPath: current, in: result)
            }
        }
        return result
    }

    /// Refresh all previously-loaded nodes, preserving lazy structure for unloaded directories.
    static func refreshLoadedNodes(in nodes: [FileNode], rootPath: String) -> [FileNode] {
        let freshRoot = buildShallowTree(rootPath: rootPath)
        return mergeNodes(fresh: freshRoot, existing: nodes, rootPath: rootPath)
    }

    // MARK: - Lookup

    static func findNode(atPath path: String, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.id == path { return node }
            if node.isDirectory, let children = node.children, path.hasPrefix(node.id + "/") {
                if let found = findNode(atPath: path, in: children) { return found }
            }
        }
        return nil
    }

    private static func buildShallowChildren(
        at directoryURL: URL,
        relativePathPrefix: String,
        rootPath: String
    ) -> [FileNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directoryURL.path) else {
            return []
        }

        var dirs: [FileNode] = []
        var files: [FileNode] = []

        for entry in entries {
            if entry == ".git" { continue }

            let relativePath = relativePathPrefix.isEmpty
                ? entry
                : relativePathPrefix + "/" + entry
            guard let resolvedURL = WorkspaceFileAccess.resolvedURL(
                for: relativePath,
                rootPath: rootPath
            ) else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: resolvedURL.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                dirs.append(FileNode(id: relativePath, name: entry, isDirectory: true, children: nil))
            } else {
                files.append(FileNode(id: relativePath, name: entry, isDirectory: false, children: []))
            }
        }

        dirs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return dirs + files
    }

    /// Merge fresh shallow nodes with existing tree, preserving loaded children.
    private static func mergeNodes(fresh: [FileNode], existing: [FileNode], rootPath: String) -> [FileNode] {
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        return fresh.map { freshNode in
            if freshNode.isDirectory,
               let existingNode = existingByID[freshNode.id],
               existingNode.isLoaded
            {
                // Previously loaded — refresh its children recursively
                let freshChildren = loadChildren(atRelativePath: freshNode.id, rootPath: rootPath)
                let mergedChildren = mergeNodes(
                    fresh: freshChildren,
                    existing: existingNode.children ?? [],
                    rootPath: rootPath
                )
                return FileNode(id: freshNode.id, name: freshNode.name, isDirectory: true, children: mergedChildren)
            } else {
                return freshNode
            }
        }
    }
}

// MARK: - DirectoryWatcher

/// Watches a directory tree for changes using macOS FSEventStream.
/// Calls `onChange` on the main thread when files are created, deleted, or renamed.
final class DirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.onChange = onChange

        let pathsToWatch = [path] as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            DirectoryWatcher.callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second coalescing latency
            FSEventStreamCreateFlags(flags)
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private static let callback: FSEventStreamCallback = {
        _, clientCallBackInfo, _, _, _, _ in
        guard let info = clientCallBackInfo else { return }
        let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
        DispatchQueue.main.async {
            watcher.onChange()
        }
    }
}
