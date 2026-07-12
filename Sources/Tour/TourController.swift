// ABOUTME: Runtime state machine for guided tours: active flow, current step,
// ABOUTME: auto-advance on app notifications, and per-flow completion stamping.

import Foundation
import SwiftUI

@MainActor
final class TourController: ObservableObject {
    static let shared = TourController()

    @Published private(set) var activeFlow: TourFlow?
    @Published private(set) var stepIndex: Int = 0

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var stepObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    var currentStep: TourStep? {
        guard let activeFlow, activeFlow.steps.indices.contains(stepIndex) else { return nil }
        return activeFlow.steps[stepIndex]
    }

    var isLastStep: Bool {
        guard let activeFlow else { return false }
        return stepIndex == activeFlow.steps.count - 1
    }

    func start(_ flow: TourFlow) {
        guard !flow.steps.isEmpty else { return }
        teardownStepObserver()
        activeFlow = flow
        stepIndex = 0
        enterCurrentStep()
    }

    func next() {
        guard activeFlow != nil else { return }
        teardownStepObserver()
        if isLastStep {
            finish()
        } else {
            stepIndex += 1
            enterCurrentStep()
        }
    }

    func skipStep() {
        next()
    }

    func quit() {
        teardownStepObserver()
        activeFlow = nil
        stepIndex = 0
    }

    static func completedKey(_ flowID: String) -> String {
        "dockyard.tourCompleted.\(flowID)"
    }

    static func isCompleted(_ flowID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey(flowID))
    }

    private func finish() {
        if let flowID = activeFlow?.id {
            defaults.set(true, forKey: Self.completedKey(flowID))
        }
        activeFlow = nil
        stepIndex = 0
    }

    private func enterCurrentStep() {
        guard let step = currentStep else { return }
        if case let .notification(name) = step.advance {
            stepObserver = notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.next()
                }
            }
        }
        step.onEnter?()
    }

    private func teardownStepObserver() {
        if let stepObserver {
            notificationCenter.removeObserver(stepObserver)
            self.stepObserver = nil
        }
    }
}
