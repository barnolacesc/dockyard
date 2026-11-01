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
        let host = json?["host"] as? [String: Any]
        XCTAssertNotNil(host)
        XCTAssertNotNil(host?["name"])
        XCTAssertNotNil(host?["defaultAgent"])
        XCTAssertNotNil(host?["defaultBypass"])
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

    // MARK: - Image Upload Tests

    func testImageUploadUnauthorized() async {
        let request = HTTPRequest(
            method: .POST,
            version: .http11,
            path: "/api/workstreams/\(UUID().uuidString)/image",
            query: [],
            headers: [:],
            body: Data("test".utf8)
        )

        let response = await CompanionServer.handleUploadImage(request: request)
        XCTAssertEqual(response.statusCode, HTTPStatusCode.unauthorized)
    }

    func testImageUploadInvalidWorkstreamUUID() async {
        let server = CompanionServer.shared
        let request = HTTPRequest(
            method: .POST,
            version: .http11,
            path: "/api/workstreams/invalid-not-a-uuid/image",
            query: [],
            headers: [
                .authorization: "Bearer \(server.token)",
                .contentType: "image/png",
            ],
            body: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        )

        let response = await CompanionServer.handleUploadImage(request: request)
        XCTAssertEqual(response.statusCode, HTTPStatusCode.badRequest)
    }

    func testImageUploadWorkstreamNotFound() async {
        let server = CompanionServer.shared
        let nonExistentID = UUID().uuidString
        let request = HTTPRequest(
            method: .POST,
            version: .http11,
            path: "/api/workstreams/\(nonExistentID)/image",
            query: [],
            headers: [
                .authorization: "Bearer \(server.token)",
                .contentType: "image/png",
            ],
            body: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        )

        let response = await CompanionServer.handleUploadImage(request: request)
        XCTAssertEqual(response.statusCode, HTTPStatusCode.notFound)
    }

    func testImageUploadUnsupportedContentType() async {
        let server = CompanionServer.shared
        let workstreamID = UUID()
        let project = Project(name: "TestProject", directory: "/tmp", workstreams: [
            Workstream(name: "ws1", id: workstreamID),
        ])
        let originalProjects = ProjectStore.load()
        ProjectStore.save([project])
        defer { ProjectStore.save(originalProjects) }

        let request = HTTPRequest(
            method: .POST,
            version: .http11,
            path: "/api/workstreams/\(workstreamID.uuidString)/image",
            query: [],
            headers: [
                .authorization: "Bearer \(server.token)",
                .contentType: "text/plain",
            ],
            body: Data("plain text not an image".utf8)
        )

        let response = await CompanionServer.handleUploadImage(request: request)
        XCTAssertEqual(response.statusCode, HTTPStatusCode.badRequest)
    }

    func testImageUploadEmptyBody() async {
        let server = CompanionServer.shared
        let workstreamID = UUID()
        let project = Project(name: "TestProject", directory: "/tmp", workstreams: [
            Workstream(name: "ws1", id: workstreamID),
        ])
        let originalProjects = ProjectStore.load()
        ProjectStore.save([project])
        defer { ProjectStore.save(originalProjects) }

        let request = HTTPRequest(
            method: .POST,
            version: .http11,
            path: "/api/workstreams/\(workstreamID.uuidString)/image",
            query: [],
            headers: [
                .authorization: "Bearer \(server.token)",
                .contentType: "image/png",
            ],
            body: Data()
        )

        let response = await CompanionServer.handleUploadImage(request: request)
        XCTAssertEqual(response.statusCode, HTTPStatusCode.badRequest)
    }

    func testImageUploadRawBinarySuccessAndPermissions() async throws {
        let server = CompanionServer.shared
        let workstreamID = UUID()
        let project = Project(name: "TestProject", directory: "/tmp", workstreams: [
            Workstream(name: "ws1", id: workstreamID),
        ])
        let originalProjects = ProjectStore.load()
        ProjectStore.save([project])
        defer { ProjectStore.save(originalProjects) }

        let uploadDir = AppConstants.uploadsDirectory.appendingPathComponent(workstreamID.uuidString.lowercased())
        defer {
            try? FileManager.default.removeItem(at: uploadDir)
        }

        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52])
        let request = HTTPRequest(
            method: .POST,
            version: .http11,
            path: "/api/workstreams/\(workstreamID.uuidString)/image",
            query: [],
            headers: [
                .authorization: "Bearer \(server.token)",
                .contentType: "image/png",
            ],
            body: pngBytes
        )

        let response = await CompanionServer.handleUploadImage(request: request)
        XCTAssertEqual(response.statusCode, HTTPStatusCode.ok)

        let responseData = try await response.bodyData
        let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any]
        let okVal = json?["ok"] as? Bool
        XCTAssertEqual(okVal, true)
        let pathVal = json?["path"] as? String
        let filePath = try XCTUnwrap(pathVal)
        XCTAssertTrue(filePath.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))

        let savedData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        XCTAssertEqual(savedData, pngBytes)

        // Check directory permissions are 0o700
        let dirAttributes = try FileManager.default.attributesOfItem(atPath: uploadDir.path)
        let posixPerms = dirAttributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(posixPerms?.intValue, 0o700)
    }

    func testImageUploadMultipartFormDataSuccess() async throws {
        let server = CompanionServer.shared
        let workstreamID = UUID()
        let project = Project(name: "TestProject", directory: "/tmp", workstreams: [
            Workstream(name: "ws1", id: workstreamID),
        ])
        let originalProjects = ProjectStore.load()
        ProjectStore.save([project])
        defer { ProjectStore.save(originalProjects) }

        let uploadDir = AppConstants.uploadsDirectory.appendingPathComponent(workstreamID.uuidString.lowercased())
        defer {
            try? FileManager.default.removeItem(at: uploadDir)
        }

        let boundary = "----TestBoundary987654321"
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

        var multipartData = Data()
        multipartData.append(Data("--\(boundary)\r\n".utf8))
        multipartData.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpeg\"\r\n".utf8))
        multipartData.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        multipartData.append(jpegBytes)
        multipartData.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let request = HTTPRequest(
            method: .POST,
            version: .http11,
            path: "/api/workstreams/\(workstreamID.uuidString)/image",
            query: [],
            headers: [
                .authorization: "Bearer \(server.token)",
                .contentType: "multipart/form-data; boundary=\(boundary)",
            ],
            body: multipartData
        )

        let response = await CompanionServer.handleUploadImage(request: request)
        XCTAssertEqual(response.statusCode, HTTPStatusCode.ok)

        let responseData = try await response.bodyData
        let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any]
        let okVal = json?["ok"] as? Bool
        XCTAssertEqual(okVal, true)
        let pathVal = json?["path"] as? String
        let filePath = try XCTUnwrap(pathVal)
        XCTAssertTrue(filePath.hasSuffix(".jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))

        let savedData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        XCTAssertEqual(savedData, jpegBytes)
    }

    func testExtractImageFormats() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0x00, 0x00])
        let gifBytes = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x00])
        var webpBytes = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00])
        webpBytes.append(Data([0x57, 0x45, 0x42, 0x50, 0x00, 0x00]))

        XCTAssertEqual(CompanionServer.extractImage(from: pngBytes, contentType: "image/png")?.ext, "png")
        XCTAssertEqual(CompanionServer.extractImage(from: jpegBytes, contentType: "image/jpeg")?.ext, "jpg")
        XCTAssertEqual(CompanionServer.extractImage(from: gifBytes, contentType: "image/gif")?.ext, "gif")
        XCTAssertEqual(CompanionServer.extractImage(from: webpBytes, contentType: "image/webp")?.ext, "webp")

        // Fallback detection without explicit mime
        XCTAssertEqual(CompanionServer.extractImage(from: pngBytes, contentType: "application/octet-stream")?.ext, "png")
        XCTAssertEqual(CompanionServer.extractImage(from: jpegBytes, contentType: "")?.ext, "jpg")
        XCTAssertEqual(CompanionServer.extractImage(from: gifBytes, contentType: "application/octet-stream")?.ext, "gif")
        XCTAssertEqual(CompanionServer.extractImage(from: webpBytes, contentType: "")?.ext, "webp")

        // Boundary extraction
        XCTAssertEqual(CompanionServer.extractBoundary(from: "multipart/form-data; boundary=my-boundary"), "my-boundary")
        XCTAssertEqual(CompanionServer.extractBoundary(from: "multipart/form-data; boundary=\"quoted-boundary\""), "quoted-boundary")
        XCTAssertNil(CompanionServer.extractBoundary(from: "image/png"))
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

            // 3. Create with explicit codingCLI and bypassPermissions
            var req3 = URLRequest(url: endpoint)
            req3.httpMethod = "POST"
            req3.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req3.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req3.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": "feature-yolo",
                "codingCLI": "agy",
                "bypassPermissions": true,
            ])

            let (data3, res3) = try await URLSession.shared.data(for: req3)
            let http3 = try XCTUnwrap(res3 as? HTTPURLResponse)
            XCTAssertEqual(http3.statusCode, 200)

            updatedProjects = ProjectStore.load()
            let savedProject3 = try XCTUnwrap(updatedProjects.first(where: { $0.id == project.id }))
            XCTAssertEqual(savedProject3.workstreams.count, 3)
            let ws3 = try XCTUnwrap(savedProject3.workstreams.first(where: { $0.name == "feature-yolo" }))
            XCTAssertEqual(ws3.codingCLI, "agy")
            XCTAssertTrue(ws3.bypassPermissions)
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
