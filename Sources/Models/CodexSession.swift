// ABOUTME: Persists the Codex-reported thread owned by a workstream.
// ABOUTME: Resolves ownership at execution time, including detached tmux respawns.

import Darwin
import Foundation

struct CodexOwnedProcess: Codable {
    let pid: Int32
    let startedAt: Date

    var isCurrent: Bool {
        guard pid > 1, let actual = RunStateStore.processStartDate(pid: pid) else { return false }
        return abs(actual.timeIntervalSince(startedAt)) < 0.001
    }
}

struct CodexSessionAssociation: Codable, Equatable {
    let threadID: UUID
    let workingDirectory: String
}

enum CodexSession {
    static func processURL(for id: UUID, directory: URL = AppConstants.configDirectory) -> URL {
        fileURL(for: id, directory: directory).deletingPathExtension().appendingPathExtension("process.json")
    }

    static func registerOwnedProcess(pid: Int32, for id: UUID, directory: URL = AppConstants.configDirectory) throws {
        guard pid > 1, let startedAt = RunStateStore.processStartDate(pid: pid) else { throw CocoaError(.fileReadUnknown) }
        try FilePersistence.writeAtomically(JSONEncoder().encode(CodexOwnedProcess(pid: pid, startedAt: startedAt)), to: processURL(for: id, directory: directory))
    }

    /// Capture the owned tree before terminal destruction can reparent children.
    /// Birth times prevent a stale record from signalling a reused PID.
    static func terminateOwnedProcesses(for id: UUID, directory: URL = AppConstants.configDirectory, beforeTermination: () -> Void = {}) {
        let url = processURL(for: id, directory: directory)
        guard let data = AgentStateFiles.readBoundedSnapshotData(from: url),
              let root = try? JSONDecoder().decode(CodexOwnedProcess.self, from: data), root.isCurrent,
              root.pid != getpid()
        else {
            beforeTermination()
            return
        }
        try? FileManager.default.removeItem(at: url)
        var tree = [root]
        var seen: Set<Int32> = [root.pid]
        var index = 0
        while index < tree.count {
            let parent = tree[index]
            index += 1
            guard parent.isCurrent else { continue }
            let count = proc_listchildpids(parent.pid, nil, 0)
            guard count > 0 else { continue }
            var children = [Int32](repeating: 0, count: Int(count) + 32)
            let actualCount = children.withUnsafeMutableBytes { proc_listchildpids(parent.pid, $0.baseAddress, Int32($0.count)) }
            guard actualCount > 0 else { continue }
            for pid in children.prefix(Int(actualCount)) where pid > 1 && !seen.contains(pid) {
                var info = proc_bsdinfo()
                let size = Int32(MemoryLayout<proc_bsdinfo>.size)
                let read = withUnsafeMutablePointer(to: &info) { proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, size) }
                if read == size, info.pbi_ppid == UInt32(parent.pid), let startedAt = RunStateStore.processStartDate(pid: pid) {
                    seen.insert(pid)
                    tree.append(CodexOwnedProcess(pid: pid, startedAt: startedAt))
                }
            }
        }
        // Stop tmux after capturing descendants, before a dying pane can respawn.
        beforeTermination()
        for process in tree.reversed() where process.isCurrent {
            _ = kill(process.pid, SIGTERM)
        }
        let captured = tree
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            for process in captured.reversed() where process.isCurrent {
                _ = kill(process.pid, SIGKILL)
            }
        }
    }

    static func fileURL(for id: UUID, directory: URL = AppConstants.configDirectory) -> URL {
        directory.appendingPathComponent("codex-sessions", isDirectory: true)
            .appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    static func canonicalDirectory(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func load(for id: UUID, workingDirectory: String, directory: URL = AppConstants.configDirectory) -> CodexSessionAssociation? {
        guard let data = AgentStateFiles.readBoundedSnapshotData(from: fileURL(for: id, directory: directory)),
              let session = try? JSONDecoder().decode(CodexSessionAssociation.self, from: data),
              session.workingDirectory == canonicalDirectory(workingDirectory)
        else { return nil }
        return session
    }

    static func remove(for id: UUID, directory: URL = AppConstants.configDirectory) {
        try? FileManager.default.removeItem(at: fileURL(for: id, directory: directory))
        try? FileManager.default.removeItem(at: processURL(for: id, directory: directory))
    }

    /// SessionStart and UserPromptSubmit supply the real session_id. Never
    /// infer ownership from Codex's history index, directory, or update time.
    static func recordHook(_ data: Data, for id: UUID, workingDirectory: String,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           directory: URL = AppConstants.configDirectory) throws
    {
        guard data.count <= AgentSubagentHookInput.maximumInputBytes,
              let input = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawID = input["session_id"] as? String, let threadID = UUID(uuidString: rawID),
              let cwd = input["cwd"] as? String,
              canonicalDirectory(cwd) == canonicalDirectory(workingDirectory),
              let event = input["hook_event_name"] as? String,
              event == "SessionStart" || event == "UserPromptSubmit"
        else { throw CocoaError(.fileReadCorruptFile) }

        let session = CodexSessionAssociation(threadID: threadID, workingDirectory: canonicalDirectory(cwd))
        try FilePersistence.writeAtomically(JSONEncoder().encode(session), to: fileURL(for: id, directory: directory))
        if event == "SessionStart", let marker = environment["DOCKYARD_CODEX_START_RECEIPT"] {
            try FilePersistence.writeAtomically(Data(rawID.utf8), to: URL(fileURLWithPath: marker))
        }
        if event == "UserPromptSubmit",
           let expected = environment["DOCKYARD_CODEX_INITIAL_PROMPT"],
           input["prompt"] as? String == expected
        {
            try FilePersistence.writeAtomically(Data(rawID.utf8), to: directory.appendingPathComponent("agent-prompts").appendingPathComponent("\(id.uuidString.lowercased()).consumed"))
        }
    }
}
