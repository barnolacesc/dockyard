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
}
