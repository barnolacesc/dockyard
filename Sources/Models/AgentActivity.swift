// ABOUTME: Persists a bounded, local history of Coding Agent state transitions.
// ABOUTME: Powers the read-only Attention inbox without retaining transcript content.

import Combine
import Foundation

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
final class AgentActivityStore: ObservableObject {
    static let shared = AgentActivityStore(agentStateStore: .shared)
    static let maximumEvents = 200
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    @Published private(set) var events: [AgentActivityEvent]

    private static let defaultsKey = "dockyard.agentActivity"
    private let defaults: UserDefaults
    private var lastObservedStates: [UUID: AgentState]
    private var stateCancellable: AnyCancellable?

    init(
        agentStateStore: AgentStateStore,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        self.defaults = defaults
        lastObservedStates = agentStateStore.states
        events = Self.loadEvents(defaults: defaults, now: now)

        stateCancellable = agentStateStore.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                self?.ingest(states: states)
            }
    }

    var unreadCount: Int {
        events.lazy.filter(\.isUnread).count
    }

    func markRead(_ eventID: UUID, at date: Date = Date()) {
        guard let index = events.firstIndex(where: { $0.id == eventID }),
              events[index].readAt == nil
        else { return }
        events[index].readAt = date
        persist()
    }

    func markAllRead(at date: Date = Date()) {
        guard events.contains(where: \.isUnread) else { return }
        for index in events.indices where events[index].readAt == nil {
            events[index].readAt = date
        }
        persist()
    }

    func ingest(states: [UUID: AgentState], at date: Date = Date()) {
        let newEvents = Self.transitions(from: lastObservedStates, to: states, at: date)
        lastObservedStates = states
        guard !newEvents.isEmpty else { return }

        let cutoff = date.addingTimeInterval(-Self.retentionInterval)
        events = Array(
            (newEvents + events)
                .filter { $0.occurredAt >= cutoff }
                .prefix(Self.maximumEvents)
        )
        persist()
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

    private static func loadEvents(defaults: UserDefaults, now: Date) -> [AgentActivityEvent] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([AgentActivityEvent].self, from: data)
        else { return [] }
        let cutoff = now.addingTimeInterval(-retentionInterval)
        return Array(
            decoded
                .filter { $0.occurredAt >= cutoff }
                .sorted { $0.occurredAt > $1.occurredAt }
                .prefix(maximumEvents)
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
