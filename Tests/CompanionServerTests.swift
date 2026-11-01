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

    // MARK: - Workstream REST Endpoint Tests

    private var originalProjects: [Project] = []
    private var testTempDir: URL?
    private var testProjectName: String?

    override func setUp() {
        super.setUp()
        originalProjects = ProjectStore.load()
    }

    override func tearDown() {
        ProjectStore.save(originalProjects)
        if let dir = testTempDir {
            try? FileManager.default.removeItem(at: dir)
            testTempDir = nil
        }
        if let name = testProjectName {
            let worktreesProjectDir = AppConstants.worktreesDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: worktreesProjectDir)
            testProjectName = nil
        }
        super.tearDown()
    }

    @discardableResult
    private func git(_ args: [String], in dir: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = dir
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func createTestRepo() throws -> (URL, String) {
        let uniqueID = UUID().uuidString.prefix(8)
        let projectName = "TestProject-\(uniqueID)"
        testProjectName = projectName
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("companion-tests-\(uniqueID)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testTempDir = tempDir
        let repoDir = tempDir.appendingPathComponent("main-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        git(["init", "-b", "main"], in: repoDir)
        git(["-c", "user.email=test@dockyard.app", "-c", "user.name=DockyardTest",
             "commit", "--allow-empty", "-m", "initial commit"], in: repoDir)
        return (repoDir, projectName)
    }

    private func withTestServer(operation: (URL, String) async throws -> Void) async throws {
        let port = Int.random(in: 20000 ... 30000)
        let server = HTTPServer(port: UInt16(port))
        CompanionServer.configureRoutes(on: server)
        let task = Task {
            try await server.run()
        }
        try await server.waitUntilListening()
        let baseURL = URL(string: "http://127.0.0.1:\(port)")!
        let token = CompanionServer.currentToken()

        do {
            try await operation(baseURL, token)
        } catch {
            await server.stop()
            task.cancel()
            throw error
        }
        await server.stop()
        task.cancel()
    }

    func testCreateWorkstreamEndpointAuthValidation() async throws {
        try await withTestServer { baseURL, _ in
            let projectID = UUID()
            let endpoint = baseURL.appendingPathComponent("api/projects/\(projectID)/workstreams")

            // 1. Missing Authorization header
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            let (_, res1) = try await URLSession.shared.data(for: req)
            let http1 = try XCTUnwrap(res1 as? HTTPURLResponse)
            XCTAssertEqual(http1.statusCode, 401)

            // 2. Invalid Bearer token
            var req2 = URLRequest(url: endpoint)
            req2.httpMethod = "POST"
            req2.setValue("Bearer invalid_token", forHTTPHeaderField: "Authorization")
            let (_, res2) = try await URLSession.shared.data(for: req2)
            let http2 = try XCTUnwrap(res2 as? HTTPURLResponse)
            XCTAssertEqual(http2.statusCode, 401)
        }
    }

    func testCreateWorkstreamEndpointValidationFailures() async throws {
        try await withTestServer { baseURL, token in
            // 1. Invalid UUID
            let invalidEndpoint = baseURL.appendingPathComponent("api/projects/not-a-valid-uuid/workstreams")
            var req1 = URLRequest(url: invalidEndpoint)
            req1.httpMethod = "POST"
            req1.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, res1) = try await URLSession.shared.data(for: req1)
            let http1 = try XCTUnwrap(res1 as? HTTPURLResponse)
            XCTAssertEqual(http1.statusCode, 400)

            // 2. Non-existent Project UUID
            let nonExistentEndpoint = baseURL.appendingPathComponent("api/projects/\(UUID())/workstreams")
            var req2 = URLRequest(url: nonExistentEndpoint)
            req2.httpMethod = "POST"
            req2.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, res2) = try await URLSession.shared.data(for: req2)
            let http2 = try XCTUnwrap(res2 as? HTTPURLResponse)
            XCTAssertEqual(http2.statusCode, 404)
        }
    }

    func testCreateWorkstreamEndpointSuccess() async throws {
        let (repoDir, projectName) = try createTestRepo()
        let project = Project(name: projectName, directory: repoDir.path)
        ProjectStore.save([project])

        try await withTestServer { baseURL, token in
            let endpoint = baseURL.appendingPathComponent("api/projects/\(project.id)/workstreams")

            // 1. Create with explicit name in payload
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["name": "feature-auth"])

            let (data1, res1) = try await URLSession.shared.data(for: req)
            let http1 = try XCTUnwrap(res1 as? HTTPURLResponse)
            XCTAssertEqual(http1.statusCode, 200)

            let json1 = try JSONSerialization.jsonObject(with: data1, options: []) as? [String: Any]
            XCTAssertEqual(json1?["ok"] as? Bool, true)
            let ws1 = try XCTUnwrap(json1?["workstream"] as? [String: Any])
            XCTAssertEqual(ws1["name"] as? String, "feature-auth")
            let branch1 = try XCTUnwrap(ws1["branch"] as? String)
            XCTAssertTrue(branch1.contains("feature-auth"))

            // Verify persisted in ProjectStore
            var updatedProjects = ProjectStore.load()
            let savedProject1 = try XCTUnwrap(updatedProjects.first(where: { $0.id == project.id }))
            XCTAssertEqual(savedProject1.workstreams.count, 1)
            XCTAssertEqual(savedProject1.workstreams.first?.name, "feature-auth")

            // 2. Create without name (generates memorable name)
            var req2 = URLRequest(url: endpoint)
            req2.httpMethod = "POST"
            req2.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req2.httpBody = try JSONSerialization.data(withJSONObject: [:])

            let (data2, res2) = try await URLSession.shared.data(for: req2)
            let http2 = try XCTUnwrap(res2 as? HTTPURLResponse)
            XCTAssertEqual(http2.statusCode, 200)

            let json2 = try JSONSerialization.jsonObject(with: data2, options: []) as? [String: Any]
            XCTAssertEqual(json2?["ok"] as? Bool, true)
            let ws2 = try XCTUnwrap(json2?["workstream"] as? [String: Any])
            let generatedName = try XCTUnwrap(ws2["name"] as? String)
            XCTAssertFalse(generatedName.isEmpty)
            XCTAssertNotEqual(generatedName, "feature-auth")

            updatedProjects = ProjectStore.load()
            let savedProject2 = try XCTUnwrap(updatedProjects.first(where: { $0.id == project.id }))
            XCTAssertEqual(savedProject2.workstreams.count, 2)
        }
    }

    func testCloseWorkstreamEndpointAuthAndValidation() async throws {
        try await withTestServer { baseURL, token in
            let wsID = UUID()
            let endpoint = baseURL.appendingPathComponent("api/workstreams/\(wsID)/close")

            // 1. Missing Authorization header
            var req1 = URLRequest(url: endpoint)
            req1.httpMethod = "POST"
            let (_, res1) = try await URLSession.shared.data(for: req1)
            let http1 = try XCTUnwrap(res1 as? HTTPURLResponse)
            XCTAssertEqual(http1.statusCode, 401)

            // 2. Invalid Bearer token
            var req2 = URLRequest(url: endpoint)
            req2.httpMethod = "POST"
            req2.setValue("Bearer bad_token", forHTTPHeaderField: "Authorization")
            let (_, res2) = try await URLSession.shared.data(for: req2)
            let http2 = try XCTUnwrap(res2 as? HTTPURLResponse)
            XCTAssertEqual(http2.statusCode, 401)

            // 3. Invalid UUID
            let invalidEndpoint = baseURL.appendingPathComponent("api/workstreams/invalid-uuid/close")
            var req3 = URLRequest(url: invalidEndpoint)
            req3.httpMethod = "POST"
            req3.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, res3) = try await URLSession.shared.data(for: req3)
            let http3 = try XCTUnwrap(res3 as? HTTPURLResponse)
            XCTAssertEqual(http3.statusCode, 400)

            // 4. Non-existent workstream UUID
            let (_, res4) = try await URLSession.shared.data(for: {
                var r = URLRequest(url: endpoint)
                r.httpMethod = "POST"
                r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return r
            }())
            let http4 = try XCTUnwrap(res4 as? HTTPURLResponse)
            XCTAssertEqual(http4.statusCode, 404)
        }
    }

    func testCloseWorkstreamEndpointSuccess() async throws {
        let ws1 = Workstream(name: "active-stream-1")
        let ws2 = Workstream(name: "active-stream-2")
        var project = Project(name: "TestProject", directory: "/tmp/fake-dir")
        project.workstreams = [ws1, ws2]
        ProjectStore.save([project])

        try await withTestServer { baseURL, token in
            let endpoint = baseURL.appendingPathComponent("api/workstreams/\(ws1.id)/close")

            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, res) = try await URLSession.shared.data(for: req)
            let http = try XCTUnwrap(res as? HTTPURLResponse)
            XCTAssertEqual(http.statusCode, 200)

            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            XCTAssertEqual(json?["ok"] as? Bool, true)

            // Verify ws1 is removed, ws2 remains
            let updatedProjects = ProjectStore.load()
            let savedProject = try XCTUnwrap(updatedProjects.first(where: { $0.id == project.id }))
            XCTAssertEqual(savedProject.workstreams.count, 1)
            XCTAssertEqual(savedProject.workstreams.first?.id, ws2.id)
        }
    }
}
