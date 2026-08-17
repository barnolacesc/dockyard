import XCTest
import Combine
@testable import Dockyard

@MainActor
final class SetupRunnerTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func waitForState(_ runner: SetupRunner, target: SetupRunner.State, timeout: TimeInterval = 5.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runner.state == target {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for state \(target). Actual state: \(runner.state)")
    }

    func test_succeeds_on_exit_zero() async throws {
        let workstreamID = UUID()
        let runner = SetupRunner(workstreamID: workstreamID)
        
        runner.start(script: "exit 0", workingDirectory: tmpDir.path)
        XCTAssertEqual(runner.state, .running)
        
        await waitForState(runner, target: .succeeded)
        XCTAssertEqual(runner.state, .succeeded)
        
        SetupStateStore.remove(for: workstreamID)
    }

    func test_fails_on_non_zero_exit() async throws {
        let workstreamID = UUID()
        let runner = SetupRunner(workstreamID: workstreamID)
        
        runner.start(script: "exit 1", workingDirectory: tmpDir.path)
        
        await waitForState(runner, target: .failed(exitCode: 1))
        XCTAssertEqual(runner.state, .failed(exitCode: 1))
        
        SetupStateStore.remove(for: workstreamID)
    }

    func test_captures_output_to_log_tail() async throws {
        let workstreamID = UUID()
        let runner = SetupRunner(workstreamID: workstreamID)
        
        runner.start(script: "echo 'hello world'", workingDirectory: tmpDir.path)
        
        await waitForState(runner, target: .succeeded)
        
        XCTAssertTrue(runner.logTail.contains("hello world"))
        
        SetupStateStore.remove(for: workstreamID)
    }

    func test_log_tail_capped_at_max_bytes() async throws {
        let workstreamID = UUID()
        let runner = SetupRunner(workstreamID: workstreamID)
        
        // Print more than 4096 bytes. Let's do 5000 'A's.
        let script = "for i in {1..5000}; do printf 'A'; done"
        
        runner.start(script: script, workingDirectory: tmpDir.path)
        
        await waitForState(runner, target: .succeeded)
        
        XCTAssertEqual(runner.logTail.count, 4096)
        XCTAssertTrue(runner.logTail.hasPrefix("A"))
        XCTAssertTrue(runner.logTail.hasSuffix("A"))
        
        SetupStateStore.remove(for: workstreamID)
    }

    func test_marks_completed_only_on_success() async throws {
        let id1 = UUID()
        let runner1 = SetupRunner(workstreamID: id1)
        runner1.start(script: "exit 1", workingDirectory: tmpDir.path)
        await waitForState(runner1, target: .failed(exitCode: 1))
        
        XCTAssertFalse(SetupStateStore.isCompleted(for: id1))
        
        let id2 = UUID()
        let runner2 = SetupRunner(workstreamID: id2)
        runner2.start(script: "exit 0", workingDirectory: tmpDir.path)
        await waitForState(runner2, target: .succeeded)
        
        XCTAssertTrue(SetupStateStore.isCompleted(for: id2))
        
        SetupStateStore.remove(for: id1)
        SetupStateStore.remove(for: id2)
    }
}

final class SetupStateStoreTests: XCTestCase {
    private let userDefaultsKey = "dockyard.setupCompleted"
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SetupStateStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_mixedPayloadPreservesValidCompletionIdentifiers() throws {
        let first = UUID()
        let second = UUID()
        let payload: [Any] = [
            first.uuidString,
            ["unexpected": true],
            "not-a-uuid",
            42,
            second.uuidString,
            NSNull(),
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: userDefaultsKey)

        XCTAssertTrue(SetupStateStore.isCompleted(for: first, defaults: defaults))
        XCTAssertTrue(SetupStateStore.isCompleted(for: second, defaults: defaults))
        XCTAssertFalse(SetupStateStore.isCompleted(for: UUID(), defaults: defaults))
    }

    func test_markCompletedPreservesRecoveredIdentifiersAndCanonicalizesStorage() throws {
        let existing = UUID()
        let added = UUID()
        let payload: [Any] = [existing.uuidString, ["unexpected": true]]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: userDefaultsKey)

        SetupStateStore.markCompleted(for: added, defaults: defaults)

        let savedData = try XCTUnwrap(defaults.data(forKey: userDefaultsKey))
        let saved = try JSONDecoder().decode(Set<String>.self, from: savedData)
        XCTAssertEqual(saved, Set([existing.uuidString, added.uuidString]))
    }

    func test_invalidTopLevelPayloadFailsClosed() throws {
        let workstreamID = UUID()
        let payload = ["completed": [workstreamID.uuidString]]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: userDefaultsKey)

        XCTAssertFalse(SetupStateStore.isCompleted(for: workstreamID, defaults: defaults))
    }

    func test_removePreservesOtherRecoveredIdentifiers() throws {
        let removed = UUID()
        let retained = UUID()
        let payload: [Any] = [removed.uuidString, false, retained.uuidString]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: userDefaultsKey)

        SetupStateStore.remove(for: removed, defaults: defaults)

        XCTAssertFalse(SetupStateStore.isCompleted(for: removed, defaults: defaults))
        XCTAssertTrue(SetupStateStore.isCompleted(for: retained, defaults: defaults))
        let savedData = try XCTUnwrap(defaults.data(forKey: userDefaultsKey))
        let saved = try JSONDecoder().decode(Set<String>.self, from: savedData)
        XCTAssertEqual(saved, Set([retained.uuidString]))
    }
}
