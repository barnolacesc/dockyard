// ABOUTME: Unit tests for GlobalTerminalState, persistence, clamping, and surface cache lifecycle.

@testable import Dockyard
import Foundation
import SwiftUI
import XCTest

/// Test suite validating global terminal state, persistence, geometry, and surface cache lifecycles.
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

    /// Tests that a freshly initialized GlobalTerminalState starts closed, unminimized, and without a surface ID.
    @MainActor
    func testInitialStateIsClosed() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        XCTAssertFalse(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertNil(state.surfaceID)
        XCTAssertNil(state.position)
    }

    /// Tests that the default working directory for the global terminal is the user's home directory.
    @MainActor
    func testInitialWorkingDirectoryIsHomeDirectory() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        XCTAssertEqual(state.workingDirectory, FileManager.default.homeDirectoryForCurrentUser.path)
        XCTAssertEqual(GlobalTerminalState.defaultWorkingDirectory, FileManager.default.homeDirectoryForCurrentUser.path)
    }

    // MARK: - Lifecycle Tests (Open, Minimize, Restore, Close)

    /// Tests that opening the global terminal generates a valid surface ID and marks state as open and unminimized.
    @MainActor
    func testOpenCreatesSurfaceID() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        state.open()

        XCTAssertTrue(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertNotNil(state.surfaceID)
    }

    /// Tests that minimizing the global terminal retains the existing surface ID and shell process.
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

    /// Tests that restoring a minimized global terminal keeps the same surface ID.
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

    /// Tests cycling through open, minimize, and restore via toggle.
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

    /// Tests that closing destroys the surface, evicts it from the cache, and a subsequent open creates a new session.
    @MainActor
    func testCloseDestroysSurfaceAndNextOpenUsesNewSession() throws {
        let cache = TerminalSurfaceCache()
        let state = GlobalTerminalState(userDefaults: testDefaults)

        state.open(surfaceCache: cache)
        let firstSurfaceID = try XCTUnwrap(state.surfaceID)
        cache.registerTestSurface(for: firstSurfaceID)

        XCTAssertTrue(cache.isSurfaceCached(for: firstSurfaceID))
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(firstSurfaceID))

        state.close(surfaceCache: cache)
        XCTAssertFalse(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertNil(state.surfaceID)
        XCTAssertFalse(cache.isSurfaceCached(for: firstSurfaceID))
        XCTAssertFalse(cache.alwaysVisibleSurfaceIDs.contains(firstSurfaceID))

        // Opening again generates a new UUID and registers a fresh session
        state.open(surfaceCache: cache)
        let secondSurfaceID = try XCTUnwrap(state.surfaceID)
        XCTAssertTrue(state.isOpen)
        XCTAssertNotEqual(secondSurfaceID, firstSurfaceID)
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(secondSurfaceID))

        cache.registerTestSurface(for: secondSurfaceID)
        XCTAssertTrue(cache.isSurfaceCached(for: secondSurfaceID))
        XCTAssertFalse(cache.isSurfaceCached(for: firstSurfaceID))
    }

    /// Tests that shell process termination cleans up surface ID, resets state, and evicts from cache.
    @MainActor
    func testProcessTerminatedResetsState() throws {
        let cache = TerminalSurfaceCache()
        let state = GlobalTerminalState(userDefaults: testDefaults)
        state.open(surfaceCache: cache)
        let surfaceID = try XCTUnwrap(state.surfaceID)
        cache.registerTestSurface(for: surfaceID)

        XCTAssertTrue(cache.isSurfaceCached(for: surfaceID))

        state.handleProcessTerminated(surfaceCache: cache)

        XCTAssertFalse(state.isOpen)
        XCTAssertFalse(state.isMinimized)
        XCTAssertNil(state.surfaceID)
        XCTAssertFalse(cache.isSurfaceCached(for: surfaceID))
        XCTAssertFalse(cache.alwaysVisibleSurfaceIDs.contains(surfaceID))
    }

    // MARK: - Persistence Tests

    /// Tests that custom panel position coordinates persist across state initializations.
    @MainActor
    func testPersistenceOfPosition() {
        let state1 = GlobalTerminalState(userDefaults: testDefaults)
        let customPos = CGPoint(x: 180, y: 220)
        state1.savePosition(customPos)

        let state2 = GlobalTerminalState(userDefaults: testDefaults)
        XCTAssertEqual(state2.position, customPos)
    }

    /// Tests that minimized state persists across state initializations.
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

    /// Tests that candidate panel positions outside window boundaries are clamped within padding bounds.
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

    /// Tests that default initial position is placed near bottom-right inside visible window boundaries.
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

    /// Tests that panel dimensions downscale proportionally on smaller windows to fit within visible viewport.
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

    // MARK: - Surface Cache Occlusion & Navigation Tests

    /// Tests that global terminal surface is tracked as always visible during occlusion updates.
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

    /// Tests that the cached terminal surface survives switching between workstreams and root views.
    @MainActor
    func testCachedSurfaceRetainedAcrossWorkstreamAndRootViewNavigation() throws {
        let cache = TerminalSurfaceCache()
        let state = GlobalTerminalState(userDefaults: testDefaults)

        state.open(surfaceCache: cache)
        let globalSurfaceID = try XCTUnwrap(state.surfaceID)
        cache.registerTestSurface(for: globalSurfaceID)

        XCTAssertTrue(cache.isSurfaceCached(for: globalSurfaceID))
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))

        // Navigate to Workstream 1
        let ws1SurfaceID = UUID()
        cache.updateOcclusion(visibleSurfaceIDs: [ws1SurfaceID])
        XCTAssertTrue(cache.isSurfaceCached(for: globalSurfaceID))
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))
        XCTAssertEqual(state.surfaceID, globalSurfaceID)

        // Navigate to Workstream 2
        let ws2SurfaceID = UUID()
        cache.updateOcclusion(visibleSurfaceIDs: [ws2SurfaceID])
        XCTAssertTrue(cache.isSurfaceCached(for: globalSurfaceID))
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))
        XCTAssertEqual(state.surfaceID, globalSurfaceID)

        // Navigate to Root Screen (Settings, Help, or Project Overview with no active workstream terminal)
        cache.updateOcclusion(visibleSurfaceIDs: [])
        XCTAssertTrue(cache.isSurfaceCached(for: globalSurfaceID))
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))
        XCTAssertEqual(state.surfaceID, globalSurfaceID)

        // Minimize global terminal while browsing root screens
        state.minimize(surfaceCache: cache)
        XCTAssertTrue(cache.isSurfaceCached(for: globalSurfaceID))
        XCTAssertFalse(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))

        // Switch to another workstream while minimized
        cache.updateOcclusion(visibleSurfaceIDs: [ws1SurfaceID])
        XCTAssertTrue(cache.isSurfaceCached(for: globalSurfaceID))

        // Restore global terminal
        state.restore(surfaceCache: cache)
        XCTAssertTrue(cache.isSurfaceCached(for: globalSurfaceID))
        XCTAssertTrue(cache.alwaysVisibleSurfaceIDs.contains(globalSurfaceID))
        XCTAssertEqual(state.surfaceID, globalSurfaceID)
    }

    // MARK: - View Hierarchy & Environment Tests

    /// Tests that FloatingTerminalPanel body evaluates cleanly when injected with TerminalSurfaceCache.
    @MainActor
    func testFloatingTerminalPanelRendersWithSurfaceCacheEnvironment() {
        let state = GlobalTerminalState(userDefaults: testDefaults)
        state.open()
        guard let surfaceID = state.surfaceID else {
            XCTFail("surfaceID should not be nil after open()")
            return
        }
        let cache = TerminalSurfaceCache()

        let panel = FloatingTerminalPanel(
            surfaceID: surfaceID,
            windowSize: CGSize(width: 800, height: 600),
            state: state,
            onClose: {},
            onMinimize: {}
        )
        .environmentObject(cache)

        let hosting = NSHostingView(rootView: panel)
        hosting.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        hosting.layout()
        XCTAssertNotNil(hosting.subviews)
    }
}
