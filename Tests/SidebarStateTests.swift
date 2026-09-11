// ABOUTME: Tests bounded restoration and persistence for sidebar selection and expansion state.
// ABOUTME: Ensures malformed or oversized defaults payloads fail closed without being deleted.

@testable import Dockyard
import XCTest

final class SidebarStateTests: XCTestCase {
    private static let testSuiteName = "dockyard.sidebar-state.tests"
    private static let selectionKey = "dockyard.selection"
    private static let expandedProjectsKey = "dockyard.expandedProjects"
    private let defaults = UserDefaults(suiteName: testSuiteName)!

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: Self.testSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.testSuiteName)
        super.tearDown()
    }

    func testSelectionAndExpandedProjectsRoundTrip() {
        let projectID = UUID()
        let expandedIDs: Set<UUID> = [projectID, UUID()]

        SidebarSelection.project(projectID).save(defaults: defaults)
        SidebarState.saveExpanded(expandedIDs, defaults: defaults)

        XCTAssertEqual(SidebarSelection.loadSaved(defaults: defaults), .project(projectID))
        XCTAssertEqual(SidebarState.loadExpanded(defaults: defaults), expandedIDs)
    }

    func testPayloadsAtByteCeilingRestore() throws {
        let selection = SidebarSelection.workstream(UUID())
        let expandedIDs: Set<UUID> = [UUID(), UUID()]
        let selectionData = try paddedJSON(selection, byteCount: SidebarPersistence.maximumSnapshotBytes)
        let expandedData = try paddedJSON(expandedIDs, byteCount: SidebarPersistence.maximumSnapshotBytes)
        defaults.set(selectionData, forKey: Self.selectionKey)
        defaults.set(expandedData, forKey: Self.expandedProjectsKey)

        XCTAssertEqual(SidebarSelection.loadSaved(defaults: defaults), selection)
        XCTAssertEqual(SidebarState.loadExpanded(defaults: defaults), expandedIDs)
    }

    func testOversizedPayloadsFallBackWithoutDeletingStoredBytes() throws {
        let selectionData = try paddedJSON(
            SidebarSelection.help,
            byteCount: SidebarPersistence.maximumSnapshotBytes + 1
        )
        let expandedData = try paddedJSON(
            Set([UUID()]),
            byteCount: SidebarPersistence.maximumSnapshotBytes + 1
        )
        defaults.set(selectionData, forKey: Self.selectionKey)
        defaults.set(expandedData, forKey: Self.expandedProjectsKey)

        XCTAssertNil(SidebarSelection.loadSaved(defaults: defaults))
        XCTAssertEqual(SidebarState.loadExpanded(defaults: defaults), [])
        XCTAssertEqual(defaults.data(forKey: Self.selectionKey), selectionData)
        XCTAssertEqual(defaults.data(forKey: Self.expandedProjectsKey), expandedData)
    }

    func testMalformedPayloadsFallBackWithoutDeletingStoredBytes() {
        let malformed = Data("not-json".utf8)
        defaults.set(malformed, forKey: Self.selectionKey)
        defaults.set(malformed, forKey: Self.expandedProjectsKey)

        XCTAssertNil(SidebarSelection.loadSaved(defaults: defaults))
        XCTAssertEqual(SidebarState.loadExpanded(defaults: defaults), [])
        XCTAssertEqual(defaults.data(forKey: Self.selectionKey), malformed)
        XCTAssertEqual(defaults.data(forKey: Self.expandedProjectsKey), malformed)
    }

    private func paddedJSON<Value: Encodable>(_ value: Value, byteCount: Int) throws -> Data {
        var data = try JSONEncoder().encode(value)
        XCTAssertLessThan(data.count, byteCount)
        data.append(Data(repeating: 0x20, count: byteCount - data.count))
        return data
    }
}
