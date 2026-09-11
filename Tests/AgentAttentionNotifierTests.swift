// ABOUTME: Verifies waiting-agent notifications, payload routing, and foreground suppression.
// ABOUTME: Uses an injected notification center so tests never contact macOS Notification Center.

@testable import Dockyard
import UserNotifications
import XCTest

@MainActor
final class AgentAttentionNotifierTests: XCTestCase {
    func testWaitingEventCreatesWorkstreamNotification() throws {
        let center = AgentNotificationCenterStub()
        let workstream = Workstream(name: "contrast-fix")
        let project = Project(
            name: "Dockyard",
            directory: "/tmp/dockyard",
            workstreams: [workstream]
        )
        let notifier = AgentAttentionNotifier(
            notificationCenter: center,
            projectsProvider: { [project] },
            applicationIsActive: { false }
        )
        let event = AgentActivityEvent(
            workstreamID: workstream.id,
            kind: .waiting,
            occurredAt: Date()
        )

        notifier.notifyIfNeeded(for: event)

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(request.identifier, "agent-attention.\(event.id.uuidString.lowercased())")
        XCTAssertEqual(request.content.title, "Dockyard")
        XCTAssertTrue(request.content.body.contains("contrast-fix"))
        XCTAssertEqual(
            AgentAttentionPayload(notificationUserInfo: request.content.userInfo),
            AgentAttentionPayload(workstreamID: workstream.id, eventID: event.id)
        )
    }

    func testOnlyWaitingEventsCreateNotifications() {
        let center = AgentNotificationCenterStub()
        let workstream = Workstream(name: "workstream")
        let project = Project(name: "Project", directory: "/tmp/project", workstreams: [workstream])
        let notifier = AgentAttentionNotifier(
            notificationCenter: center,
            projectsProvider: { [project] },
            applicationIsActive: { false }
        )

        for kind in [AgentActivityKind.started, .completed, .inactive] {
            notifier.notifyIfNeeded(
                for: AgentActivityEvent(workstreamID: workstream.id, kind: kind, occurredAt: Date())
            )
        }

        XCTAssertTrue(center.requests.isEmpty)
    }

    func testVisibleAgentSuppressesNotificationOnlyWhileAppIsActive() {
        let activeCenter = AgentNotificationCenterStub()
        let workstream = Workstream(name: "workstream")
        let project = Project(name: "Project", directory: "/tmp/project", workstreams: [workstream])
        let event = AgentActivityEvent(workstreamID: workstream.id, kind: .waiting, occurredAt: Date())
        let activeNotifier = AgentAttentionNotifier(
            notificationCenter: activeCenter,
            projectsProvider: { [project] },
            applicationIsActive: { true }
        )
        activeNotifier.setAgentVisible(true, for: workstream.id)

        activeNotifier.notifyIfNeeded(for: event)

        XCTAssertTrue(activeCenter.requests.isEmpty)

        let backgroundCenter = AgentNotificationCenterStub()
        let backgroundNotifier = AgentAttentionNotifier(
            notificationCenter: backgroundCenter,
            projectsProvider: { [project] },
            applicationIsActive: { false }
        )
        backgroundNotifier.setAgentVisible(true, for: workstream.id)

        backgroundNotifier.notifyIfNeeded(for: event)

        XCTAssertEqual(backgroundCenter.requests.count, 1)
    }

    func testPayloadRejectsMalformedOrUnrelatedNotifications() {
        XCTAssertNil(AgentAttentionPayload(notificationUserInfo: [:]))
        XCTAssertNil(AgentAttentionPayload(notificationUserInfo: ["kind": "other"]))
        XCTAssertNil(AgentAttentionPayload(notificationUserInfo: [
            "kind": AgentAttentionPayload.kind,
            "workstreamID": "invalid",
            "eventID": UUID().uuidString,
        ]))
    }
}

@MainActor
private final class AgentNotificationCenterStub: AgentNotificationRequestAdding {
    private(set) var requests: [UNNotificationRequest] = []

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    ) {
        requests.append(request)
        completionHandler?(nil)
    }
}
