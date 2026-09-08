// ABOUTME: Tests Monaco resource requests stay contained and use bounded regular-file reads.
// ABOUTME: Covers response metadata plus oversized, growing, symlink, directory, and FIFO inputs.

@testable import Dockyard
import Darwin
import Foundation
import WebKit
import XCTest

@MainActor
final class MonacoResourceSchemeHandlerTests: XCTestCase {
    private let baseURL = URL(
        fileURLWithPath: "/Applications/Dockyard.app/Contents/Resources/MonacoEditor",
        isDirectory: true
    )

    func testAcceptsDirectAndNestedDescendants() {
        let directChild = baseURL.appendingPathComponent("index.html")
        let nestedChild = baseURL.appendingPathComponent("assets/editor/main.js")

        XCTAssertTrue(
            MonacoResourceSchemeHandler.isContainedResourceURL(directChild, within: baseURL)
        )
        XCTAssertTrue(
            MonacoResourceSchemeHandler.isContainedResourceURL(nestedChild, within: baseURL)
        )
    }

    func testRejectsTraversalOutsideResourceRoot() {
        let traversal = URL(
            fileURLWithPath: baseURL.path + "/../Secrets/config.json"
        )

        XCTAssertFalse(
            MonacoResourceSchemeHandler.isContainedResourceURL(traversal, within: baseURL)
        )
    }

    func testRejectsSiblingWithSharedStringPrefix() {
        let sibling = URL(
            fileURLWithPath: baseURL.path + "Backup/index.html"
        )

        XCTAssertFalse(
            MonacoResourceSchemeHandler.isContainedResourceURL(sibling, within: baseURL)
        )
    }

    func testRejectsResourceRootItself() {
        XCTAssertFalse(
            MonacoResourceSchemeHandler.isContainedResourceURL(baseURL, within: baseURL)
        )
    }

    func testBoundedReaderAcceptsRegularResourceAtLimit() throws {
        let root = temporaryResourceDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resourceURL = root.appendingPathComponent("main.js")
        let expected = Data(repeating: 0x61, count: 32)
        try expected.write(to: resourceURL)

        let actual = try MonacoResourceSchemeHandler.readResourceData(
            at: resourceURL,
            maximumBytes: 32
        )

        XCTAssertEqual(actual, expected)
    }

    func testBoundedReaderRejectsOversizedRegularResource() throws {
        let root = temporaryResourceDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resourceURL = root.appendingPathComponent("main.js")
        try Data(repeating: 0x61, count: 33).write(to: resourceURL)

        XCTAssertThrowsError(
            try MonacoResourceSchemeHandler.readResourceData(at: resourceURL, maximumBytes: 32)
        )
    }

    func testBoundedReaderRejectsResourceThatGrowsAfterMetadataCheck() throws {
        let root = temporaryResourceDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resourceURL = root.appendingPathComponent("main.js")
        try Data(repeating: 0x61, count: 32).write(to: resourceURL)

        XCTAssertThrowsError(
            try MonacoResourceSchemeHandler.readResourceData(
                at: resourceURL,
                maximumBytes: 32
            ) {
                guard let handle = try? FileHandle(forWritingTo: resourceURL) else { return }
                handle.seekToEndOfFile()
                handle.write(Data([0x62]))
                handle.closeFile()
            }
        )
    }

    func testBoundedReaderRejectsSymbolicLink() throws {
        let root = temporaryResourceDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let targetURL = root.appendingPathComponent("target.js")
        let linkURL = root.appendingPathComponent("main.js")
        try Data("resource".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        XCTAssertThrowsError(
            try MonacoResourceSchemeHandler.readResourceData(at: linkURL, maximumBytes: 32)
        )
    }

    func testBoundedReaderRejectsDirectory() throws {
        let root = temporaryResourceDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directoryURL = root.appendingPathComponent("main.js", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try MonacoResourceSchemeHandler.readResourceData(at: directoryURL, maximumBytes: 32)
        )
    }

    func testBoundedReaderRejectsFIFOWithoutBlocking() throws {
        let root = temporaryResourceDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fifoURL = root.appendingPathComponent("main.js")
        XCTAssertEqual(mkfifo(fifoURL.path, 0o600), 0)

        XCTAssertThrowsError(
            try MonacoResourceSchemeHandler.readResourceData(at: fifoURL, maximumBytes: 32)
        )
    }

    func testSchemeHandlerPreservesSuccessfulResponseMetadata() throws {
        let root = temporaryResourceDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resourceData = Data("const ready = true;".utf8)
        try resourceData.write(to: root.appendingPathComponent("main.js"))
        let task = URLSchemeTaskSpy(url: try XCTUnwrap(URL(string: "ff-resource://monaco/main.js")))

        MonacoResourceSchemeHandler(baseURL: root, maximumResourceBytes: 32)
            .webView(WKWebView(), start: task)

        let response = try XCTUnwrap(task.response as? HTTPURLResponse)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "text/javascript")
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Length"), "19")
        XCTAssertEqual(task.data, resourceData)
        XCTAssertTrue(task.finished)
        XCTAssertNil(task.error)
    }

    func testSchemeHandlerFailsOversizedResourceThroughExistingErrorPath() throws {
        let root = temporaryResourceDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 33).write(to: root.appendingPathComponent("main.js"))
        let task = URLSchemeTaskSpy(url: try XCTUnwrap(URL(string: "ff-resource://monaco/main.js")))

        MonacoResourceSchemeHandler(baseURL: root, maximumResourceBytes: 32)
            .webView(WKWebView(), start: task)

        XCTAssertEqual((task.error as? URLError)?.code, .fileDoesNotExist)
        XCTAssertNil(task.response)
        XCTAssertTrue(task.data.isEmpty)
        XCTAssertFalse(task.finished)
    }

    private func temporaryResourceDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dockyard-monaco-resource-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class URLSchemeTaskSpy: NSObject, WKURLSchemeTask {
    let request: URLRequest
    private(set) var response: URLResponse?
    private(set) var data = Data()
    private(set) var finished = false
    private(set) var error: Error?

    init(url: URL) {
        request = URLRequest(url: url)
    }

    func didReceive(_ response: URLResponse) {
        self.response = response
    }

    func didReceive(_ data: Data) {
        self.data.append(data)
    }

    func didFinish() {
        finished = true
    }

    func didFailWithError(_ error: any Error) {
        self.error = error
    }
}
