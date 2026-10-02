// ABOUTME: Keeps issue prompts available after failed launches and omits them after successful sessions.
// ABOUTME: A persistent receipt is shared by Dockyard and tmux respawns, including while the app is closed.

import Foundation

/// Manages persistent receipt tracking for one-shot initial agent prompt seeds.
enum AgentInitialPrompt {
    /// Returns the file URL for the receipt that records when a workstream's initial prompt has been consumed.
    ///
    /// - Parameters:
    ///   - workstreamID: The unique identifier of the target workstream.
    ///   - directory: Base configuration directory for receipts (defaults to AppConstants.configDirectory).
    /// - Returns: A file URL pointing to the `.consumed` receipt file.
    static func receiptURL(for workstreamID: UUID, directory: URL = AppConstants.configDirectory) -> URL {
        directory.appendingPathComponent("agent-prompts", isDirectory: true)
            .appendingPathComponent("\(workstreamID.uuidString.lowercased()).consumed")
    }

    /// There is no shared ingestion acknowledgment across the supported CLIs.
    /// Keep the seed until the interactive command exits successfully; failures can retry it.
    ///
    /// - Parameters:
    ///   - command: The initial command containing the prompt seed.
    ///   - continuation: The fallback command invoked when the receipt already exists.
    ///   - receiptURL: The filesystem location to write the receipt upon exit 0.
    /// - Returns: A shell command string that writes the receipt on successful session completion.
    static func wrap(command: String, continuation: String, receiptURL: URL) -> String {
        let receipt = CommandBuilder.shellQuote(receiptURL.path)
        let directory = CommandBuilder.shellQuote(receiptURL.deletingLastPathComponent().path)
        let script = """
        if [ -f \(receipt) ]; then
          \(continuation)
        else
          mkdir -p \(directory) || exit $?
          \(command)
          dockyard_agent_status=$?
          if [ "$dockyard_agent_status" -eq 0 ]; then
            touch \(receipt) || exit $?
          fi
          exit "$dockyard_agent_status"
        fi
        """
        return "/bin/sh -c \(CommandBuilder.shellQuote(script))"
    }
}
