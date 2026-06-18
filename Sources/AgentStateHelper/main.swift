// ABOUTME: dy-agent-state helper. Invoked by coding agent lifecycle hooks to
// ABOUTME: write JSON state at ~/Library/Caches/dockyard/agent-state/<wsID>.json.

import Darwin
import Foundation

let arguments = CommandLine.arguments

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: dy-agent-state --workstream-id <uuid> --state <working|waiting|idle>\n".utf8))
    exit(2)
}

func value(for flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

guard let idString = value(for: "--workstream-id"),
      let id = UUID(uuidString: idString),
      let stateString = value(for: "--state"),
      let state = AgentState(rawValue: stateString)
else {
    usage()
}

// Record the parent agent process pid rather than our own. The helper exits
// immediately, but the agent process stays alive. The store's loadValidated()
// uses this for liveness checks.
let agentPID = getppid()
let snapshot = AgentStateSnapshot(state: state, updatedAt: Date(), pid: agentPID)

do {
    try FileManager.default.createDirectory(at: AgentStateFiles.directoryURL, withIntermediateDirectories: true)
    try AgentStateFiles.write(snapshot, for: id)
    exit(0)
} catch {
    FileHandle.standardError.write(Data("dy-agent-state: write failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
