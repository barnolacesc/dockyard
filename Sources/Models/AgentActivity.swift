// ABOUTME: Observes Coding Agent state transitions for system notifications.
// ABOUTME: Does not retain activity history; the Attention view reads live agent state.

import Combine
import Foundation

extension Notification.Name {
    static let agentActivityEventsAdded = Notification.Name("dockyard.agentActivityEventsAdded")
}

enum AgentActivityKind: String, Codable, Equatable {
    case started
    case waiting
    case completed
    case inactive

    var systemImage: String {
        switch self {
        case .started: "bolt.fill"
        case .waiting: "questionmark.bubble.fill"
        case .completed: "checkmark.circle.fill"
        case .inactive: "pause.circle.fill"
        }
    }

    var titleKey: String {
        switch self {
        case .started: "Agent started working"
        case .waiting: "Agent needs your attention"
        case .completed: "Agent finished a turn"
        case .inactive: "Agent became inactive"
        }
    }
}

struct AgentActivityEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let workstreamID: UUID
    let kind: AgentActivityKind
    let occurredAt: Date
    var readAt: Date?

    init(
        id: UUID = UUID(),
        workstreamID: UUID,
        kind: AgentActivityKind,
        occurredAt: Date,
        readAt: Date? = nil
    ) {
        self.id = id
        self.workstreamID = workstreamID
        self.kind = kind
        self.occurredAt = occurredAt
        self.readAt = readAt
    }

    var isUnread: Bool {
        readAt == nil
    }
}

@MainActor
final class AgentActivityStore {
    static let shared = AgentActivityStore(agentStateStore: .shared)
    private static let legacyDefaultsKey = "dockyard.agentActivity"
    private var lastObservedStates: [UUID: AgentState]
    private var stateCancellable: AnyCancellable?

    init(agentStateStore: AgentStateStore) {
        // Attention used to persist an event timeline. Clear it once now that
        // the UI is driven exclusively by live agent state.
        UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
        lastObservedStates = agentStateStore.states

        stateCancellable = agentStateStore.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                self?.ingest(states: states)
            }
    }

    func ingest(states: [UUID: AgentState], at date: Date = Date()) {
        let newEvents = Self.transitions(from: lastObservedStates, to: states, at: date)
        lastObservedStates = states
        guard !newEvents.isEmpty else { return }

        NotificationCenter.default.post(name: .agentActivityEventsAdded, object: newEvents)
    }

    static func transitions(
        from previous: [UUID: AgentState],
        to current: [UUID: AgentState],
        at date: Date
    ) -> [AgentActivityEvent] {
        let ids = Set(previous.keys).union(current.keys).sorted { $0.uuidString < $1.uuidString }
        return ids.compactMap { workstreamID in
            let oldState = previous[workstreamID]
            let newState = current[workstreamID]
            guard oldState != newState else { return nil }

            let kind: AgentActivityKind
            switch newState {
            case .working: kind = .started
            case .waiting: kind = .waiting
            case .idle: kind = .completed
            case nil:
                guard oldState == .working || oldState == .waiting else { return nil }
                kind = .inactive
            }
            return AgentActivityEvent(workstreamID: workstreamID, kind: kind, occurredAt: date)
        }
    }

}
