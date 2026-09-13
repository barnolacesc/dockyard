// ABOUTME: Prevents idle system sleep according to the user's caffeinate mode.
// ABOUTME: Tracks live Coding Agent activity and owns the macOS power assertion.

import Combine
import Foundation
import IOKit.pwr_mgt
import os

private let caffeinateLogger = Logger(subsystem: "dockyard", category: "caffeinate")

enum CaffeinateMode: String, CaseIterable, Identifiable {
    case off
    case whileAgentsWork
    case always

    static let storageKey = "dockyard.caffeinateMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            NSLocalizedString("Off", comment: "Caffeinate mode option")
        case .whileAgentsWork:
            NSLocalizedString("While Coding Agents Work", comment: "Caffeinate mode option")
        case .always:
            NSLocalizedString("Always", comment: "Caffeinate mode option")
        }
    }
}

protocol SleepAssertionManaging: AnyObject, Sendable {
    func setActive(_ active: Bool)
}

final class SystemSleepAssertion: SleepAssertionManaging, @unchecked Sendable {
    private var assertionID: IOPMAssertionID?

    func setActive(_ active: Bool) {
        if active {
            acquire()
        } else {
            release()
        }
    }

    deinit {
        release()
    }

    private func acquire() {
        guard assertionID == nil else { return }

        var newAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Dockyard Caffeinate Mode" as CFString,
            &newAssertionID
        )
        guard result == kIOReturnSuccess else {
            caffeinateLogger.error("Failed to prevent idle system sleep: \(result)")
            return
        }
        assertionID = newAssertionID
    }

    private func release() {
        guard let assertionID else { return }
        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            caffeinateLogger.warning("Failed to release idle system sleep assertion: \(result)")
        }
        self.assertionID = nil
    }
}

@MainActor
final class CaffeinateController {
    static let shared = CaffeinateController()

    private let agentStateStore: AgentStateStore
    private let defaults: UserDefaults
    private let sleepAssertion: SleepAssertionManaging
    private var stateCancellable: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?

    init(
        agentStateStore: AgentStateStore = .shared,
        defaults: UserDefaults = .standard,
        sleepAssertion: SleepAssertionManaging = SystemSleepAssertion()
    ) {
        self.agentStateStore = agentStateStore
        self.defaults = defaults
        self.sleepAssertion = sleepAssertion
    }

    func start() {
        guard stateCancellable == nil, defaultsObserver == nil else { return }

        stateCancellable = agentStateStore.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        refresh()
    }

    func refresh() {
        let rawMode = defaults.string(forKey: CaffeinateMode.storageKey)
        let mode = rawMode.flatMap(CaffeinateMode.init(rawValue:)) ?? .off
        sleepAssertion.setActive(Self.shouldPreventSleep(mode: mode, states: agentStateStore.states))
    }

    static func shouldPreventSleep(mode: CaffeinateMode, states: [UUID: AgentState]) -> Bool {
        switch mode {
        case .off:
            false
        case .whileAgentsWork:
            states.values.contains(.working)
        case .always:
            true
        }
    }
}
