// ABOUTME: Tests for browser web view caching in TerminalSurfaceCache.
// ABOUTME: Verifies cached WKWebView instances are reused across tab switches.

@testable import Dockyard
import WebKit
import XCTest

@MainActor
final class BrowserViewTests: XCTestCase {
    func testBrowserBridgePersistsStateWithPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-browser-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("state.json")
        let state = BrowserBridge.State(
            url: "http://localhost:4321",
            title: "Preview",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            consoleLog: []
        )

        try BrowserBridge.persist(state, to: file)

        XCTAssertEqual(try permissions(of: root), 0o700)
        XCTAssertEqual(try permissions(of: file), 0o600)
        XCTAssertEqual(try BrowserBridge.decodeState(at: file).url, state.url)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["state.json"])
    }

    func testBrowserBridgeRepairsPermissiveStatePermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-browser-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try Data("legacy".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        let state = BrowserBridge.State(
            url: "https://example.test",
            title: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            consoleLog: []
        )

        try BrowserBridge.persist(state, to: file)

        XCTAssertEqual(try permissions(of: root), 0o700)
        XCTAssertEqual(try permissions(of: file), 0o600)
        XCTAssertEqual(try BrowserBridge.decodeState(at: file).url, state.url)
    }

    func testBrowserBridgeDecodesStateAtMaximumSize() throws {
        let root = temporaryBrowserStateDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("state.json")
        var data = try encodedBrowserStateData()
        XCTAssertLessThan(data.count, BrowserBridge.maximumStateBytes)
        data.append(Data(repeating: 0x20, count: BrowserBridge.maximumStateBytes - data.count))
        try data.write(to: file)

        let decoded = try BrowserBridge.decodeState(at: file)

        XCTAssertEqual(decoded.url, "https://example.test")
        XCTAssertEqual(data.count, BrowserBridge.maximumStateBytes)
    }

    func testBrowserBridgeRejectsOversizedState() throws {
        let root = temporaryBrowserStateDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("state.json")
        var data = try encodedBrowserStateData()
        data.append(Data(repeating: 0x20, count: BrowserBridge.maximumStateBytes - data.count + 1))
        try data.write(to: file)

        XCTAssertThrowsError(try BrowserBridge.decodeState(at: file))
        XCTAssertEqual(data.count, BrowserBridge.maximumStateBytes + 1)
    }

    func testBrowserBridgeRejectsSymbolicLinkState() throws {
        let root = temporaryBrowserStateDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("outside.json")
        let link = root.appendingPathComponent("state.json")
        try encodedBrowserStateData().write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try BrowserBridge.decodeState(at: link))
    }

    func testBrowserBridgeRejectsNonRegularState() throws {
        let root = temporaryBrowserStateDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directoryCandidate = root.appendingPathComponent("state.json", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryCandidate, withIntermediateDirectories: false)

        XCTAssertThrowsError(try BrowserBridge.decodeState(at: directoryCandidate))
    }

    func testBrowserBridgeRejectsMalformedState() throws {
        let root = temporaryBrowserStateDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("state.json")
        try Data("{not-json".utf8).write(to: file)

        XCTAssertThrowsError(try BrowserBridge.decodeState(at: file))
    }

    func testWebViewCacheReturnsSameInstance() {
        let cache = TerminalSurfaceCache()
        let id = UUID()

        let first = cache.webView(for: id)
        let second = cache.webView(for: id)

        XCTAssertTrue(first === second, "Cache should return the same WKWebView instance")
    }

    func testWebViewCacheReturnsDifferentInstancesForDifferentIDs() {
        let cache = TerminalSurfaceCache()
        let id1 = UUID()
        let id2 = UUID()

        let view1 = cache.webView(for: id1)
        let view2 = cache.webView(for: id2)

        XCTAssertFalse(view1 === view2, "Different IDs should get different WKWebView instances")
    }

    func testRemoveWebViewClearsCache() {
        let cache = TerminalSurfaceCache()
        let id = UUID()

        let first = cache.webView(for: id)
        cache.removeWebView(for: id)
        let second = cache.webView(for: id)

        XCTAssertFalse(first === second, "After removal, a new WKWebView instance should be created")
    }

    func testCoordinatorConformsToWKUIDelegate() {
        let webView = WKWebView()
        let representable = WebViewRepresentable(
            webView: webView,
            isLoading: .constant(false),
            canGoBack: .constant(false),
            canGoForward: .constant(false),
            urlText: .constant(""),
            connectionError: .constant(false),
            pageTitle: .constant(nil)
        )
        let coordinator = representable.makeCoordinator()
        XCTAssertTrue(coordinator is WKUIDelegate, "Coordinator should conform to WKUIDelegate")
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }

    private func encodedBrowserStateData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(
            BrowserBridge.State(
                url: "https://example.test",
                title: "Preview",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                consoleLog: []
            )
        )
    }

    private func temporaryBrowserStateDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-browser-state-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
