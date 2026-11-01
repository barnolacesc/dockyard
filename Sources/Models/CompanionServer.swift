// ABOUTME: Embedded HTTP and WebSocket server for the Dockyard Mobile Companion PWA.
// ABOUTME: Exposes fleet status, live terminal mirror, and remote steering actions.

import Combine
import FlyingFox
import Foundation

final class CompanionServer: ObservableObject, @unchecked Sendable {
    static let shared = CompanionServer()

    static let defaultPort: Int = 7890
    static let tokenStorageKey = "dockyard.companionToken"
    static let portStorageKey = "dockyard.companionPort"
    static let enabledStorageKey = "dockyard.companionEnabled"

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var connectedClientsCount: Int = 0
    @Published private(set) var localIP: String?
    @Published private(set) var tailscaleIP: String?
    @Published private(set) var currentPort: Int = defaultPort

    private var server: HTTPServer?
    private var serverTask: Task<Void, Never>?
    private var netService: NetService?
    private var cancellables = Set<AnyCancellable>()

    private static let clientsLock = NSLock()
    private nonisolated(unsafe) static var clientContinuations: [UUID: AsyncStream<WSMessage>.Continuation] = [:]

    init() {
        currentPort = UserDefaults.standard.integer(forKey: Self.portStorageKey)
        if currentPort <= 0 {
            currentPort = Self.defaultPort
        }
        setupStateObservation()
        if UserDefaults.standard.bool(forKey: Self.enabledStorageKey) {
            start()
        }
    }

    deinit {
        stop()
    }

    // MARK: - Token & URLs

    var token: String {
        Self.currentToken()
    }

    static func currentToken() -> String {
        if let existing = UserDefaults.standard.string(forKey: tokenStorageKey), !existing.isEmpty {
            return existing
        }
        let newToken = generateToken()
        UserDefaults.standard.set(newToken, forKey: tokenStorageKey)
        return newToken
    }

    func rotateToken() {
        let newToken = Self.generateToken()
        UserDefaults.standard.set(newToken, forKey: Self.tokenStorageKey)
        Self.disconnectAllClients()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectedClientsCount = 0
            self.objectWillChange.send()
        }
    }

    private static func generateToken() -> String {
        "dy_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    var localURL: URL? {
        guard let ip = localIP ?? Self.resolveLocalIP() else { return nil }
        return URL(string: "http://\(ip):\(currentPort)/?token=\(token)")
    }

    var tailscaleURL: URL? {
        guard let ip = tailscaleIP ?? Self.resolveTailscaleIP() else { return nil }
        return URL(string: "http://\(ip):\(currentPort)/?token=\(token)")
    }

    var bestPairingURL: URL? {
        tailscaleURL ?? localURL
    }

    // MARK: - Lifecycle

    func start(port: Int? = nil) {
        guard !isRunning else { return }

        let targetPort = port ?? currentPort
        currentPort = targetPort
        UserDefaults.standard.set(targetPort, forKey: Self.portStorageKey)
        UserDefaults.standard.set(true, forKey: Self.enabledStorageKey)

        localIP = Self.resolveLocalIP()
        tailscaleIP = Self.resolveTailscaleIP()

        let server = HTTPServer(port: UInt16(targetPort))
        self.server = server

        Self.configureRoutes(on: server)

        serverTask = Task { [server] in
            do {
                try await server.run()
            } catch {
                if !(error is CancellationError) {
                    NSLog("[Dockyard] Companion server error: \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                CompanionServer.shared.isRunning = false
            }
        }

        publishBonjour(port: targetPort)
        isRunning = true
    }

    func stop() {
        UserDefaults.standard.set(false, forKey: Self.enabledStorageKey)
        stopBonjour()
        Self.disconnectAllClients()

        if let server {
            Task {
                await server.stop()
            }
            self.server = nil
        }

        serverTask?.cancel()
        serverTask = nil
        isRunning = false
        connectedClientsCount = 0
    }

    // MARK: - Route Configuration

    private static func configureRoutes(on server: HTTPServer) {
        Task {
            // Static PWA Files
            await server.appendRoute("GET /") { request in
                handleIndexHTML(request)
            }
            await server.appendRoute("GET /index.html") { request in
                handleIndexHTML(request)
            }
            await server.appendRoute("GET /manifest.json") { _ in
                serveStaticFile(named: "manifest", extension: "json", contentType: "application/manifest+json")
            }
            await server.appendRoute("GET /app.js") { _ in
                serveStaticFile(named: "app", extension: "js", contentType: "application/javascript; charset=utf-8")
            }
            await server.appendRoute("GET /app.css") { _ in
                serveStaticFile(named: "app", extension: "css", contentType: "text/css; charset=utf-8")
            }
            await server.appendRoute("GET /icon.svg") { _ in
                serveStaticFile(named: "icon", extension: "svg", contentType: "image/svg+xml")
            }

            // REST API
            await server.appendRoute("GET /api/status") { request in
                guard isAuthorized(request) else {
                    return HTTPResponse(statusCode: .unauthorized, headers: [.contentType: "application/json"], body: Data("{\"error\":\"unauthorized\"}".utf8))
                }
                let data = buildStatusJSON()
                return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json; charset=utf-8"], body: data)
            }

            await server.appendRoute("GET /api/workstreams/:id/terminal") { request in
                guard isAuthorized(request) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
                guard let idStr = request.routeParameters["id"], let id = UUID(uuidString: idStr) else {
                    return HTTPResponse(statusCode: .badRequest)
                }
                let lines = Int(request.query["lines"] ?? "") ?? 150
                let text = captureWorkstreamTerminal(workstreamID: id, lines: lines) ?? "Session offline or idle"
                return HTTPResponse(statusCode: .ok, headers: [.contentType: "text/plain; charset=utf-8"], body: Data(text.utf8))
            }

            await server.appendRoute("POST /api/workstreams/:id/input") { request in
                guard isAuthorized(request) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
                guard let idStr = request.routeParameters["id"], let id = UUID(uuidString: idStr) else {
                    return HTTPResponse(statusCode: .badRequest)
                }
                let body = try? await request.bodyData
                struct InputPayload: Codable {
                    let text: String
                    let pressEnter: Bool?
                }
                let payload = body.flatMap { try? JSONDecoder().decode(InputPayload.self, from: $0) }
                let text = payload?.text ?? ""
                let pressEnter = payload?.pressEnter ?? true

                sendWorkstreamInput(workstreamID: id, text: text, pressEnter: pressEnter)
                return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: Data("{\"ok\":true}".utf8))
            }

            await server.appendRoute("POST /api/workstreams/:id/approve") { request in
                guard isAuthorized(request) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
                guard let idStr = request.routeParameters["id"], let id = UUID(uuidString: idStr) else {
                    return HTTPResponse(statusCode: .badRequest)
                }
                sendWorkstreamInput(workstreamID: id, text: "y", pressEnter: true)
                return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: Data("{\"ok\":true}".utf8))
            }

            await server.appendRoute("POST /api/workstreams/:id/deny") { request in
                guard isAuthorized(request) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
                guard let idStr = request.routeParameters["id"], let id = UUID(uuidString: idStr) else {
                    return HTTPResponse(statusCode: .badRequest)
                }
                sendWorkstreamInput(workstreamID: id, text: "n", pressEnter: true)
                return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: Data("{\"ok\":true}".utf8))
            }

            await server.appendRoute("POST /api/workstreams/:id/interrupt") { request in
                guard isAuthorized(request) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
                guard let idStr = request.routeParameters["id"], let id = UUID(uuidString: idStr) else {
                    return HTTPResponse(statusCode: .badRequest)
                }
                sendWorkstreamInterrupt(workstreamID: id)
                return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: Data("{\"ok\":true}".utf8))
            }

            // WebSocket
            await server.appendRoute("GET /ws") { request in
                guard isAuthorized(request) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
                let wsHandler = MessageFrameWSHandler(handler: CompanionWSMessageHandler())
                return HTTPResponse(webSocket: wsHandler)
            }
        }
    }

    // MARK: - Handlers

    private static func handleIndexHTML(_ request: HTTPRequest) -> HTTPResponse {
        var headers: HTTPHeaders = [
            .contentType: "text/html; charset=utf-8",
            .cacheControl: "no-cache",
        ]

        let token = currentToken()
        if let queryToken = request.query["token"], queryToken == token {
            headers[.setCookie] = "dockyard_token=\(token); Path=/; SameSite=Lax; Max-Age=31536000"
        }

        let body = loadStaticFileData(named: "index", extension: "html") ?? Data("<!DOCTYPE html><html><body>Dockyard</body></html>".utf8)
        return HTTPResponse(statusCode: .ok, headers: headers, body: body)
    }

    private static func serveStaticFile(named name: String, extension ext: String, contentType: String) -> HTTPResponse {
        guard let data = loadStaticFileData(named: name, extension: ext) else {
            return HTTPResponse(statusCode: .notFound)
        }
        return HTTPResponse(
            statusCode: .ok,
            headers: [
                .contentType: contentType,
                .cacheControl: "public, max-age=3600",
            ],
            body: data
        )
    }

    private static func loadStaticFileData(named name: String, extension ext: String) -> Data? {
        if let bundleURL = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Web") {
            if let data = try? Data(contentsOf: bundleURL) {
                return data
            }
        }
        // Fallback to relative path from project repository during dev
        let candidate = URL(fileURLWithPath: "Resources/Web/\(name).\(ext)")
        return try? Data(contentsOf: candidate)
    }

    private static func isAuthorized(_ request: HTTPRequest) -> Bool {
        let token = currentToken()
        if let q = request.query["token"], q == token { return true }
        if let auth = request.headers[.authorization], auth == "Bearer \(token)" { return true }
        if let cookie = request.headers[.cookie], cookie.contains("dockyard_token=\(token)") { return true }
        return false
    }

    // MARK: - State Serialization

    static func buildStatusJSON() -> Data {
        let projects = ProjectStore.load()
        let agentStates = AgentStateStore.shared.states
        let subagentCounts = AgentStateStore.shared.activeSubagentCounts
        let chromeActives = AgentStateStore.shared.chromeActiveWorkstreamIDs

        var projectDicts: [[String: Any]] = []

        for p in projects {
            var wsDicts: [[String: Any]] = []
            for ws in p.workstreams {
                let workDir = ws.workingDirectory(projectDirectory: p.directory)
                let branch = GitOperations.currentBranch(at: workDir) ?? ws.name
                let stateStr = agentStates[ws.id]?.rawValue ?? "idle"
                let subagents = subagentCounts[ws.id] ?? 0
                let chrome = chromeActives.contains(ws.id)
                let runSnapshot = RunStateStore.loadValidated(for: ws.id)
                let ports = runSnapshot?.detectedPorts ?? []

                wsDicts.append([
                    "id": ws.id.uuidString.lowercased(),
                    "name": ws.name,
                    "branch": branch,
                    "agentState": stateStr,
                    "activeSubagents": subagents,
                    "chromeActive": chrome,
                    "listeningPorts": ports,
                ])
            }

            projectDicts.append([
                "id": p.id.uuidString.lowercased(),
                "name": p.name,
                "directory": p.directory,
                "workstreams": wsDicts,
            ])
        }

        let hostDict: [String: Any] = [
            "name": Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.7",
        ]

        let fullPayload: [String: Any] = [
            "type": "snapshot",
            "host": hostDict,
            "projects": projectDicts,
        ]

        return (try? JSONSerialization.data(withJSONObject: fullPayload)) ?? Data("{}".utf8)
    }

    // MARK: - Tmux Actions

    private static func resolveTmuxSession(for workstreamID: UUID) -> (tmuxPath: String, sessionName: String)? {
        guard let tmuxPath = CommandLineTools.path(for: "tmux") ?? defaultTmuxPath() else {
            return nil
        }
        let projects = ProjectStore.load()
        for p in projects {
            for ws in p.workstreams where ws.id == workstreamID {
                let codexSession = TmuxSession.codexSessionName(workstreamID: ws.id)
                if TmuxSession.sessionExists(tmuxPath: tmuxPath, sessionName: codexSession) {
                    return (tmuxPath, codexSession)
                }
                let agentSession = TmuxSession.sessionName(project: p.name, workstream: ws.name, role: "agent")
                return (tmuxPath, agentSession)
            }
        }
        return nil
    }

    private static func defaultTmuxPath() -> String? {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func captureWorkstreamTerminal(workstreamID: UUID, lines: Int) -> String? {
        guard let (tmuxPath, sessionName) = resolveTmuxSession(for: workstreamID) else {
            return nil
        }
        return TmuxSession.capturePane(tmuxPath: tmuxPath, sessionName: sessionName, lines: lines)
    }

    private static func sendWorkstreamInput(workstreamID: UUID, text: String, pressEnter: Bool) {
        guard let (tmuxPath, sessionName) = resolveTmuxSession(for: workstreamID) else {
            return
        }
        TmuxSession.sendKeys(tmuxPath: tmuxPath, sessionName: sessionName, text: text, pressEnter: pressEnter)
    }

    private static func sendWorkstreamInterrupt(workstreamID: UUID) {
        guard let (tmuxPath, sessionName) = resolveTmuxSession(for: workstreamID) else {
            return
        }
        TmuxSession.sendInterrupt(tmuxPath: tmuxPath, sessionName: sessionName)
    }

    // MARK: - WebSockets & State Observation

    private func setupStateObservation() {
        AgentStateStore.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastCurrentSnapshot()
            }
            .store(in: &cancellables)
    }

    static func registerWSClient(id: UUID, continuation: AsyncStream<WSMessage>.Continuation) {
        clientsLock.lock()
        clientContinuations[id] = continuation
        let count = clientContinuations.count
        clientsLock.unlock()

        DispatchQueue.main.async {
            CompanionServer.shared.connectedClientsCount = count
        }

        let initialData = buildStatusJSON()
        if let jsonStr = String(data: initialData, encoding: .utf8) {
            continuation.yield(.text(jsonStr))
        }
    }

    static func unregisterWSClient(id: UUID) {
        clientsLock.lock()
        clientContinuations.removeValue(forKey: id)
        let count = clientContinuations.count
        clientsLock.unlock()

        DispatchQueue.main.async {
            CompanionServer.shared.connectedClientsCount = count
        }
    }

    private static func disconnectAllClients() {
        clientsLock.lock()
        for (_, continuation) in clientContinuations {
            continuation.finish()
        }
        clientContinuations.removeAll()
        clientsLock.unlock()
    }

    func broadcastCurrentSnapshot() {
        let data = Self.buildStatusJSON()
        guard let str = String(data: data, encoding: .utf8) else { return }

        Self.clientsLock.lock()
        let active = Array(Self.clientContinuations.values)
        Self.clientsLock.unlock()

        for c in active {
            c.yield(.text(str))
        }
    }

    // MARK: - Bonjour & Network Discovery

    private func publishBonjour(port: Int) {
        stopBonjour()
        let service = NetService(
            domain: "local.",
            type: "_dockyard._tcp.",
            name: Host.current().localizedName ?? "Dockyard",
            port: Int32(port)
        )
        service.publish()
        netService = service
    }

    private func stopBonjour() {
        netService?.stop()
        netService = nil
    }

    private static func resolveLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)

            if addrFamily == UInt8(AF_INET) {
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    address = hostname.withUnsafeBufferPointer { ptr in
                        ptr.baseAddress.map { String(cString: $0) }
                    }
                    if address != nil { break }
                }
            }
        }
        return address
    }

    private static func resolveTailscaleIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)

            if addrFamily == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = hostname.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress.map { String(cString: $0) }
                } ?? ""
                // Tailscale CGNAT range is 100.64.0.0/10 (100.64.0.0 – 100.127.255.255)
                if ip.hasPrefix("100.") || name.contains("tailscale") {
                    return ip
                }
            }
        }
        return nil
    }
}

// MARK: - CompanionWSMessageHandler

private struct CompanionWSMessageHandler: WSMessageHandler, @unchecked Sendable {
    func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage> {
        let clientID = UUID()

        return AsyncStream<WSMessage> { continuation in
            CompanionServer.registerWSClient(id: clientID, continuation: continuation)

            continuation.onTermination = { @Sendable _ in
                CompanionServer.unregisterWSClient(id: clientID)
            }

            Task {
                for await message in client {
                    // Handle client incoming ping/messages
                    if case let .text(text) = message {
                        if text == "ping" {
                            continuation.yield(.text("pong"))
                        }
                    }
                }
            }
        }
    }
}
