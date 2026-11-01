// ABOUTME: Unit tests for CompanionServer and Mobile Companion PWA bridge.
// ABOUTME: Tests authentication token rotation, status JSON generation, and client connections.

@testable import Dockyard
import FlyingFox
import XCTest

final class CompanionServerTests: XCTestCase {
    func testTokenGenerationAndRotation() {
        let server = CompanionServer.shared
        let initialToken = server.token
        XCTAssertFalse(initialToken.isEmpty)
        XCTAssertTrue(initialToken.hasPrefix("dy_"), "Companion token should have 'dy_' prefix")
        XCTAssertEqual(initialToken.count, 35, "Companion token should be 'dy_' + 32 hex characters")

        server.rotateToken()
        let newToken = server.token
        XCTAssertFalse(newToken.isEmpty)
        XCTAssertTrue(newToken.hasPrefix("dy_"))
        XCTAssertEqual(newToken.count, 35)
        XCTAssertNotEqual(initialToken, newToken, "Token rotation should produce a new token")
    }

    func testURLConstructionWithToken() {
        let server = CompanionServer.shared
        if let localURL = server.localURL {
            XCTAssertEqual(localURL.scheme, "http")
            XCTAssertEqual(localURL.port, server.currentPort)
            let components = URLComponents(url: localURL, resolvingAgainstBaseURL: false)
            let tokenQuery = components?.queryItems?.first(where: { $0.name == "token" })?.value
            XCTAssertEqual(tokenQuery, server.token)
        }

        if let tailscaleURL = server.tailscaleURL {
            XCTAssertEqual(tailscaleURL.scheme, "http")
            XCTAssertEqual(tailscaleURL.port, server.currentPort)
            let components = URLComponents(url: tailscaleURL, resolvingAgainstBaseURL: false)
            let tokenQuery = components?.queryItems?.first(where: { $0.name == "token" })?.value
            XCTAssertEqual(tokenQuery, server.token)
        }
    }

    func testBuildStatusJSON() throws {
        let data = CompanionServer.buildStatusJSON()
        XCTAssertFalse(data.isEmpty)

        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["type"] as? String, "snapshot")
        XCTAssertNotNil(json?["host"])
        XCTAssertNotNil(json?["projects"])
    }

    @MainActor
    func testWSClientRegistrationLifecycle() async throws {
        let server = CompanionServer.shared
        let initialCount = server.connectedClientsCount
        let clientID = UUID()

        let (stream, continuation) = AsyncStream<FlyingFox.WSMessage>.makeStream()
        _ = stream // keep alive

        CompanionServer.registerWSClient(id: clientID, continuation: continuation)

        for _ in 0 ..< 20 {
            if server.connectedClientsCount == initialCount + 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(server.connectedClientsCount, initialCount + 1)

        CompanionServer.unregisterWSClient(id: clientID)

        for _ in 0 ..< 20 {
            if server.connectedClientsCount == initialCount { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(server.connectedClientsCount, initialCount)
    }

    func testTmuxCaptureNonExistentSessionGraceful() {
        let result = TmuxSession.capturePane(
            tmuxPath: "/usr/bin/false",
            sessionName: "nonexistent-dockyard-session-\(UUID().uuidString)",
            lines: 50,
            socket: "dockyard-test"
        )
        XCTAssertNil(result, "Capturing non-existent session should return nil without throwing")
    }

    func testTmuxSendKeysNonExistentSessionGraceful() {
        // Should not crash or throw
        TmuxSession.sendKeys(
            tmuxPath: "/usr/bin/false",
            sessionName: "nonexistent-dockyard-session-\(UUID().uuidString)",
            text: "echo hello",
            pressEnter: true,
            socket: "dockyard-test"
        )

        TmuxSession.sendInterrupt(
            tmuxPath: "/usr/bin/false",
            sessionName: "nonexistent-dockyard-session-\(UUID().uuidString)",
            socket: "dockyard-test"
        )
    }

    func testTmuxListSessionsAndSanitize() {
        XCTAssertEqual(TmuxSession.sanitize("my project:test.1"), "my-project-test-1")
        let sessions = TmuxSession.listSessions(tmuxPath: "/usr/bin/false", socket: "nonexistent-socket")
        XCTAssertTrue(sessions.isEmpty)
    }
}
