// ABOUTME: Unit tests for GlobalTerminalState, persistence, clamping, and surface cache lifecycle.

@testable import Dockyard
import Foundation
import XCTest

final class GlobalTerminalTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private let suiteName = "GlobalTerminalTestsSuite"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - State & Working Directory Tests

    @MainActor
    func testInitialStateIsClosed() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        XCTAssertFalse(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertNil(state.surfaceID)
        XCTAssertNil(state.position)
    }

    @MainActor
    func testInitialWorkingDirectoryIsHomeDirectory() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        XCTAssertEqual(state.workingDirectory, FileManager.default.homeDirectoryForCurrentUser.path)
        XCTAssertEqual(GlobalTerminalState.defaultWorkingDirectory, FileManager.default.homeDirectoryForCurrentUser.path)
    }

    // MARK: - Lifecycle Tests (Open, Minimize, Restore, Close)

    @MainActor
    func testOpenCreatesSurfaceID() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        state.open()

        XCTAssertTrue(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertNotNil(state.surfaceID)
    }

    @MainActor
    func testMinimizePreservesSurfaceID() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        state.open()
        let originalID = state.surfaceID

        state.minimize()

        XCTAssertTrue(state.isOpen)
        XCTAssertTrue(state.isMinimized)
        XCTAssertEqual(state.surfaceID, originalID)
    }

    @MainActor
    func testRestorePreservesSurfaceID() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        state.open()
        let originalID = state.surfaceID

        state.minimize()
        state.restore()

        XCTAssertTrue(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertEqual(state.surfaceID, originalID)
    }

    @MainActor
    func testToggleCyclesStates() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        // Closed -> Open
        state.toggle()
        XCTAssertTrue(state.isOpen)
        XCTAssertFalse(state.isMinimized)

        let surfaceID = state.surfaceID

        // Open -> Minimized
        state.toggle()
        XCTAssertTrue(state.isOpen)
        XCTAssertTrue(state.isMinimized)
        XCTAssertEqual(state.surfaceID, surfaceID)

        // Minimized -> Restored
        state.toggle()
        XCTAssertTrue(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertEqual(state.surfaceID, surfaceID)
    }

    @MainActor
    func testCloseDestroysSurfaceAndNextOpenUsesNewSession() throws {
        let cache = TerminalSurfaceCache()
        let state = GlobalTerminalState(userDefaults: testDefaults)

        state.open(surfaceCache: cache)
        guard let firstSurfaceID = state.surfaceID else {
            XCTFail("surfaceID should be non-nil after open")
            return
        }
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(firstSurfaceID))

        state.close(surfaceCache: cache)
        XCTAssertFalse(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertNil(state.surfaceID)
        XCTAssertFalse(cache.alwaysVisibleSurfaceIDs.contains(firstSurfaceID))

        // Opening again generates a new UUID
        state.open(surfaceCache: cache)
        XCTAssertTrue(state.isOpen)
        XCTAssertNotNil(state.surfaceID)
        XCTAssertNotEqual(state.surfaceID, firstSurfaceID)
        XCTAssertTrue(try cache.alwaysVisibleSurfaceIDs.contains(XCTUnwrap(state.surfaceID)))
    }

    @MainActor
    func testProcessTerminatedResetsState() throws {
        let cache = TerminalSurfaceCache()
        let state = GlobalTerminalState(userDefaults: testDefaults)
        state.open(surfaceCache: cache)
        let surfaceID = try XCTUnwrap(state.surfaceID)

        state.handleProcessTerminated(surfaceCache: cache)

        XCTAssertFalse(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertNil(state.surfaceID)
        XCTAssertFalse(cache.alwaysVisibleSurfaceIDs.contains(surfaceID))
    }

    // MARK: - Persistence Tests

    @MainActor
    func testPersistenceOfPosition() {
        let state1 = GlobalTerminalState(userDefaults: testDefaults)
        let customPos = CGPoint(x: 180, y: 220)
        state1.savePosition(customPos)

        let state2 = GlobalTerminalState(userDefaults: testDefaults)
        XCTAssertEqual(state2.position, customPos)
    }

    @MainActor
    func testPersistenceOfMinimizedState() {
        let state1 = GlobalTerminalState(userDefaults: testDefaults)
        state1.open()
        state1.minimize()

        let state2 = GlobalTerminalState(userDefaults: testDefaults)
        XCTAssertTrue(state2.isMinimized)
        XCTAssertTrue(state2.isOpen)
        XCTAssertNotNil(state2.surfaceID)
    }

    // MARK: - Clamping & Geometry Tests

    func testClampedPositionWithinWindowBounds() {
        let windowSize = CGSize(width: 1200, height: 800)
        let panelSize = CGSize(width: 640, height: 400)
        let padding: CGFloat = 12

        // Normal inside point stays unchanged
        let normal = CGPoint(x: 100, y: 150)
        let clampedNormal = GlobalTerminalState.clampedPosition(normal, panelSize: panelSize, windowSize: windowSize, padding: padding)
        XCTAssertEqual(clampedNormal, normal)

        // Negative coordinates clamp to padding
        let negative = CGPoint(x: -50, y: -20)
        let clampedNegative = GlobalTerminalState.clampedPosition(negative, panelSize: panelSize, windowSize: windowSize, padding: padding)
        XCTAssertEqual(clampedNegative, CGPoint(x: padding, y: padding))

        // Exceeding bounds clamp to windowSize - panelSize - padding
        let exceeding = CGPoint(x: 1500, y: 1000)
        let clampedExceeding = GlobalTerminalState.clampedPosition(exceeding, panelSize: panelSize, windowSize: windowSize, padding: padding)
        let expectedX = windowSize.width - panelSize.width - padding
        let expectedY = windowSize.height - panelSize.height - padding
        XCTAssertEqual(clampedExceeding, CGPoint(x: expectedX, y: expectedY))
    }

    func testDefaultPositionNearBottomRight() {
        let windowSize = CGSize(width: 1200, height: 800)
        let panelSize = CGSize(width: 640, height: 400)

        let defaultPos = GlobalTerminalState.defaultPosition(panelSize: panelSize, windowSize: windowSize)
        XCTAssertGreaterThan(defaultPos.x, 400)
        XCTAssertGreaterThan(defaultPos.y, 250)

        // Must be fully inside window bounds
        let clamped = GlobalTerminalState.clampedPosition(defaultPos, panelSize: panelSize, windowSize: windowSize)
        XCTAssertEqual(defaultPos, clamped)
    }

    func testEffectivePanelSizeAdaptsToSmallWindows() {
        let largeWindow = CGSize(width: 1400, height: 900)
        let largePanelSize = GlobalTerminalState.effectivePanelSize(windowSize: largeWindow)
        XCTAssertEqual(largePanelSize.width, GlobalTerminalState.defaultWidth)
        XCTAssertEqual(largePanelSize.height, GlobalTerminalState.defaultHeight)

        let smallWindow = CGSize(width: 500, height: 300)
        let smallPanelSize = GlobalTerminalState.effectivePanelSize(windowSize: smallWindow)
        XCTAssertLessThanOrEqual(smallPanelSize.width, 500 - GlobalTerminalState.padding * 2)
        XCTAssertLessThanOrEqual(smallPanelSize.height, 300 - GlobalTerminalState.padding * 2)
    }

    // MARK: - Surface Cache Occlusion Tests

    @MainActor
    func testGlobalSurfaceRemainsVisibleDuringOcclusionUpdates() {
        let cache = TerminalSurfaceCache()
        let globalSurfaceID = UUID()

        // Set global surface as always visible
        cache.setSurfaceAlwaysVisible(globalSurfaceID, isAlwaysVisible: true)
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))

        // Emulate workstream navigation: update occlusion with a different workstream's surface
        let workstreamSurfaceID = UUID()
        cache.updateOcclusion(visibleSurfaceIDs: [workstreamSurfaceID])

        // The global surface ID should still be tracked as always visible
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))

        // When minimized/hidden:
        cache.setSurfaceAlwaysVisible(globalSurfaceID, isAlwaysVisible: false)
        XCTAssertFalse(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))
    }
}
