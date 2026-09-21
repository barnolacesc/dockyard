// ABOUTME: dy-agent-state helper. Invoked by coding agent lifecycle hooks to
// ABOUTME: write JSON state at ~/Library/Caches/dockyard/agent-state/<wsID>.json.

import Darwin
import Foundation

let arguments = CommandLine.arguments

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: dy-agent-state --workstream-id <uuid> [--state <working|waiting|idle>] [--chrome-active <true|false>] [--subagent-event <start|stop>]\n".utf8))
    exit(2)
}

func value(for flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func readBoundedStandardInput(maximumBytes: Int) throws -> Data? {
    var data = Data()
    while data.count <= maximumBytes {
        let remaining = maximumBytes + 1 - data.count
        let chunk = try FileHandle.standardInput.read(upToCount: min(64 * 1024, remaining)) ?? Data()
        if chunk.isEmpty {
            return data
        }
        data.append(chunk)
    }
    return nil
}

func readBoundedStandardInputIfAvailable(maximumBytes: Int) throws -> Data? {
    guard isatty(STDIN_FILENO) == 0 else { return nil }
    var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    let pollResult = poll(&fds, 1, 50)
    guard pollResult > 0, (fds.revents & Int16(POLLIN)) != 0 else { return nil }
    return try readBoundedStandardInput(maximumBytes: maximumBytes)
}

guard let idString = value(for: "--workstream-id"),
      let id = UUID(uuidString: idString)
else {
    usage()
}

let requestedState: AgentState?
if let stateString = value(for: "--state") {
    guard let state = AgentState(rawValue: stateString) else { usage() }
    requestedState = state
} else {
    requestedState = nil
}

let requestedChromeActive: Bool?
if let chromeActiveString = value(for: "--chrome-active") {
    guard let chromeActive = Bool(chromeActiveString) else { usage() }
    requestedChromeActive = chromeActive
} else {
    requestedChromeActive = nil
}

enum SubagentEvent: String {
    case start
    case stop
}

let requestedSubagentEvent: SubagentEvent?
if let eventString = value(for: "--subagent-event") {
    guard let event = SubagentEvent(rawValue: eventString) else { usage() }
    requestedSubagentEvent = event
} else {
    requestedSubagentEvent = nil
}

guard requestedState != nil || requestedChromeActive != nil || requestedSubagentEvent != nil else {
    usage()
}

guard requestedSubagentEvent == nil || (requestedState == nil && requestedChromeActive == nil) else { usage() }

/// Record the parent agent process pid rather than our own. The helper exits
/// immediately, but the agent process stays alive. The store's loadValidated()
/// uses this for liveness checks.
let agentPID = getppid()

if let requestedSubagentEvent {
    do {
        guard let inputData = try readBoundedStandardInput(
            maximumBytes: AgentSubagentHookInput.maximumInputBytes
        ) else {
            FileHandle.standardError.write(Data("dy-agent-state: subagent hook input is too large\n".utf8))
            exit(2)
        }
        if let jsonObject = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
           let error = jsonObject["error"] as? String,
           !error.isEmpty {
            FileHandle.standardOutput.write(Data("{}\n".utf8))
            exit(0)
        }
        let inputs = AgentSubagentHookInput.decodeAllValidated(from: inputData)
        guard !inputs.isEmpty else {
            FileHandle.standardError.write(Data("dy-agent-state: invalid subagent hook input\n".utf8))
            exit(2)
        }
        try FileManager.default.createDirectory(
            at: AgentStateFiles.directoryURL,
            withIntermediateDirectories: true
        )
        for input in inputs {
            switch requestedSubagentEvent {
            case .start:
                try AgentSubagentFiles.write(
                    AgentSubagentSnapshot(
                        workstreamID: id,
                        agentID: input.agentID,
                        agentType: input.agentType,
                        updatedAt: Date(),
                        pid: agentPID
                    )
                )
            case .stop:
                if input.agentID == "*" {
                    AgentSubagentFiles.removeAll(for: id)
                } else {
                    try AgentSubagentFiles.remove(workstreamID: id, agentID: input.agentID)
                }
            }
        }
        FileHandle.standardOutput.write(Data("{}\n".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("dy-agent-state: subagent state failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let existingSnapshot = AgentStateFiles.load(for: id)
let snapshot = AgentStateSnapshot(
    state: requestedState ?? existingSnapshot?.state ?? .idle,
    updatedAt: Date(),
    pid: agentPID,
    chromeActive: requestedChromeActive ?? existingSnapshot?.chromeActive ?? false
)

do {
    try FileManager.default.createDirectory(at: AgentStateFiles.directoryURL, withIntermediateDirectories: true)
    try AgentStateFiles.write(snapshot, for: id)
    if requestedState == .idle {
        var shouldRemoveSubagents = true
        if let stopData = try? readBoundedStandardInputIfAvailable(maximumBytes: AgentSubagentHookInput.maximumInputBytes),
           let jsonObject = try? JSONSerialization.jsonObject(with: stopData) as? [String: Any],
           let fullyIdle = jsonObject["fullyIdle"] as? Bool {
            shouldRemoveSubagents = fullyIdle
        }
        if shouldRemoveSubagents {
            AgentSubagentFiles.removeAll(for: id)
        }
    }
    if requestedState == .waiting {
        FileHandle.standardOutput.write(Data("{\"decision\": \"allow\"}\n".utf8))
    } else {
        FileHandle.standardOutput.write(Data("{}\n".utf8))
    }
    exit(0)
} catch {
    FileHandle.standardError.write(Data("dy-agent-state: write failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
