// ABOUTME: Tests for TourController step state, notification advancement, and completion stamping.

import XCTest
@testable import Dockyard

@MainActor
final class TourControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var center: NotificationCenter!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "TourControllerTests")!
        defaults.removePersistentDomain(forName: "TourControllerTests")
        center = NotificationCenter()
    }

    private func makeController() -> TourController {
        TourController(defaults: defaults, notificationCenter: center)
    }

    private let signal = Notification.Name("test.signal")
    private let otherSignal = Notification.Name("test.other")

    private func makeFlow(onEnterFirst: (() -> Void)? = nil) -> TourFlow {
        TourFlow(id: "test-flow", steps: [
            TourStep(id: "one", anchor: nil, titleKey: "t1", bodyKey: "b1",
                     advance: .notification(signal), onEnter: onEnterFirst),
            TourStep(id: "two", anchor: nil, titleKey: "t2", bodyKey: "b2",
                     advance: .manual),
        ])
    }

    func testStartActivatesFirstStepAndRunsOnEnter() {
        var entered = false
        let controller = makeController()
        controller.start(makeFlow(onEnterFirst: { entered = true }))
        XCTAssertEqual(controller.stepIndex, 0)
        XCTAssertEqual(controller.currentStep?.id, "one")
        XCTAssertTrue(entered)
        XCTAssertFalse(controller.isLastStep)
    }

    func testNotificationAdvancesActionStep() {
        let controller = makeController()
        controller.start(makeFlow())
        center.post(name: signal, object: nil)
        XCTAssertEqual(controller.stepIndex, 1)
        XCTAssertTrue(controller.isLastStep)
    }

    func testUnrelatedNotificationDoesNotAdvance() {
        let controller = makeController()
        controller.start(makeFlow())
        center.post(name: otherSignal, object: nil)
        XCTAssertEqual(controller.stepIndex, 0)
    }

    func testStaleSignalDoesNotAdvanceManualStep() {
        let controller = makeController()
        controller.start(makeFlow())
        center.post(name: signal, object: nil)
        XCTAssertEqual(controller.stepIndex, 1)
        // Step two is manual; the old signal must be unsubscribed.
        center.post(name: signal, object: nil)
        XCTAssertEqual(controller.stepIndex, 1)
    }

    func testNextOnLastStepFinishesAndStampsCompletion() {
        let controller = makeController()
        controller.start(makeFlow())
        controller.next()
        XCTAssertEqual(controller.stepIndex, 1)
        controller.next()
        XCTAssertNil(controller.activeFlow)
        XCTAssertTrue(TourController.isCompleted("test-flow", defaults: defaults))
    }

    func testSkipStepAdvancesLikeNext() {
        let controller = makeController()
        controller.start(makeFlow())
        controller.skipStep()
        XCTAssertEqual(controller.stepIndex, 1)
    }

    func testQuitClearsStateWithoutStamping() {
        let controller = makeController()
        controller.start(makeFlow())
        controller.quit()
        XCTAssertNil(controller.activeFlow)
        XCTAssertFalse(TourController.isCompleted("test-flow", defaults: defaults))
    }

    func testRestartAfterQuitBeginsAtStepZero() {
        let controller = makeController()
        controller.start(makeFlow())
        controller.next()
        controller.quit()
        controller.start(makeFlow())
        XCTAssertEqual(controller.stepIndex, 0)
    }

    func testStartWithEmptyFlowIsIgnored() {
        let controller = makeController()
        controller.start(TourFlow(id: "empty", steps: []))
        XCTAssertNil(controller.activeFlow)
        XCTAssertNil(controller.currentStep)
    }
}
