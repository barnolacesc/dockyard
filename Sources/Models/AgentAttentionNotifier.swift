// ABOUTME: Delivers actionable macOS notifications for agents waiting on user input.
// ABOUTME: Keeps notification presentation separate from agent activity persistence.

import AppKit
import Foundation
import os
import UserNotifications

private let agentAttentionLogger = Logger(subsystem: "dockyard", category: "agent-attention")

@MainActor
protocol AgentNotificationRequestAdding {
    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    )
}

extension UNUserNotificationCenter: AgentNotificationRequestAdding {}

struct AgentAttentionPayload: Equatable, Sendable {
    static let kind = "agent-attention"

    let workstreamID: UUID
    let eventID: UUID

    init(workstreamID: UUID, eventID: UUID) {
        self.workstreamID = workstreamID
        self.eventID = eventID
    }

    init?(notificationUserInfo: [AnyHashable: Any]) {
        guard notificationUserInfo["kind"] as? String == Self.kind,
              let workstreamString = notificationUserInfo["workstreamID"] as? String,
              let eventString = notificationUserInfo["eventID"] as? String,
              let workstreamID = UUID(uuidString: workstreamString),
              let eventID = UUID(uuidString: eventString)
        else { return nil }
        self.init(workstreamID: workstreamID, eventID: eventID)
    }

    var notificationUserInfo: [AnyHashable: Any] {
        [
            "kind": Self.kind,
            "workstreamID": workstreamID.uuidString.lowercased(),
            "eventID": eventID.uuidString.lowercased(),
        ]
    }
}

@MainActor
final class AgentAttentionNotifier {
    static let shared = AgentAttentionNotifier()

    private let notificationCenter: AgentNotificationRequestAdding
    private let projectsProvider: () -> [Project]
    private let applicationIsActive: () -> Bool
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    private var visibleAgentWorkstreamIDs = Set<UUID>()

    init(
        notificationCenter: AgentNotificationRequestAdding = UNUserNotificationCenter.current(),
        projectsProvider: @escaping () -> [Project] = { ProjectStore.load() },
        applicationIsActive: @escaping () -> Bool = { NSApp.isActive }
    ) {
        self.notificationCenter = notificationCenter
        self.projectsProvider = projectsProvider
        self.applicationIsActive = applicationIsActive
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .agentActivityEventsAdded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let events = notification.object as? [AgentActivityEvent] else { return }
            Task { @MainActor [weak self] in
                for event in events {
                    self?.notifyIfNeeded(for: event)
                }
            }
        }
    }

    func setAgentVisible(_ visible: Bool, for workstreamID: UUID) {
        if visible {
            visibleAgentWorkstreamIDs.insert(workstreamID)
        } else {
            visibleAgentWorkstreamIDs.remove(workstreamID)
        }
    }

    func notifyIfNeeded(for event: AgentActivityEvent) {
        guard event.kind == .waiting else { return }
        guard !(applicationIsActive() && visibleAgentWorkstreamIDs.contains(event.workstreamID)) else { return }
        guard let context = workstreamContext(for: event.workstreamID) else { return }

        let content = UNMutableNotificationContent()
        content.title = context.projectName
        let format = NSLocalizedString(
            "Coding Agent needs your attention in “%@”.",
            comment: "System notification shown when an agent is waiting for user input"
        )
        content.body = String(format: format, context.workstreamName)
        content.sound = UNNotificationSound(named: UNNotificationSoundName("notification.wav"))
        content.userInfo = AgentAttentionPayload(
            workstreamID: event.workstreamID,
            eventID: event.id
        ).notificationUserInfo

        let request = UNNotificationRequest(
            identifier: "agent-attention.\(event.id.uuidString.lowercased())",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { error in
            guard let error else { return }
            agentAttentionLogger.warning(
                "Failed to deliver agent attention notification: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func workstreamContext(for workstreamID: UUID) -> (projectName: String, workstreamName: String)? {
        for project in projectsProvider() {
            if let workstream = project.workstreams.first(where: { $0.id == workstreamID }) {
                return (project.name, workstream.name)
            }
        }
        return nil
    }
}
