// ABOUTME: Tests for collapsed sidebar rail mapping, status bubbling, and mode persistence.

@testable import Dockyard
import XCTest

final class SidebarRailTests: XCTestCase {
    private static let testSuiteName = "dockyard.sidebar-rail.tests"
    private let defaults = UserDefaults(suiteName: testSuiteName)!

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.testSuiteName)
        super.tearDown()
    }

    func testProjectNumberMappingUsesManualOrder() {
        let oldest = Project(
            name: "oldest",
            directory: "/repo/oldest",
            id: UUID(),
            lastAccessedAt: Date(timeIntervalSince1970: 10)
        )
        let newest = Project(
            name: "newest",
            directory: "/repo/newest",
            id: UUID(),
            lastAccessedAt: Date(timeIntervalSince1970: 30)
        )
        let middle = Project(
            name: "middle",
            directory: "/repo/middle",
            id: UUID(),
            lastAccessedAt: Date(timeIntervalSince1970: 20)
        )

        let sorted = sidebarRailSortedProjects([oldest, newest, middle])

        XCTAssertEqual(sorted.map(\.id), [oldest.id, newest.id, middle.id])
        XCTAssertEqual(sorted.indices.map(sidebarRailProjectLabel), ["1", "2", "3"])
    }

    func testWorkstreamLetterMappingUsesManualOrder() {
        let a = Workstream(name: "a", id: UUID(), lastAccessedAt: Date(timeIntervalSince1970: 10))
        let b = Workstream(name: "b", id: UUID(), lastAccessedAt: Date(timeIntervalSince1970: 30))
        let c = Workstream(name: "c", id: UUID(), lastAccessedAt: Date(timeIntervalSince1970: 20))

        let sorted = sidebarRailSortedWorkstreams([a, b, c])

        XCTAssertEqual(sorted.map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(sorted.indices.map(sidebarRailWorkstreamLabel), ["a", "b", "c"])
    }

    func testCollapsedProjectStatusBubblesWaitingAndDirtyWorkstreams() {
        let clean = Workstream(name: "clean", id: UUID())
        let waiting = Workstream(name: "waiting", id: UUID())
        let dirty = Workstream(name: "dirty", id: UUID())
        let project = Project(name: "app", directory: "/app", workstreams: [clean, waiting, dirty])

        let status = sidebarRailProjectStatus(
            for: project,
            waitingWorkstreamIDs: [waiting.id],
            dirtyCountsByWorkstreamID: [dirty.id: 4]
        )

        XCTAssertEqual(status, SidebarRailStatus(isWaiting: true, dirtyCount: 4))
    }

    func testExpandedProjectShowsStatusPerWorkstream() {
        let waiting = Workstream(name: "waiting", id: UUID())
        let dirty = Workstream(name: "dirty", id: UUID())

        let waitingStatus = sidebarRailWorkstreamStatus(
            for: waiting,
            waitingWorkstreamIDs: [waiting.id],
            dirtyCountsByWorkstreamID: [dirty.id: 2]
        )
        let dirtyStatus = sidebarRailWorkstreamStatus(
            for: dirty,
            waitingWorkstreamIDs: [waiting.id],
            dirtyCountsByWorkstreamID: [dirty.id: 2]
        )

        XCTAssertEqual(waitingStatus, SidebarRailStatus(isWaiting: true, dirtyCount: 0))
        XCTAssertEqual(dirtyStatus, SidebarRailStatus(isWaiting: false, dirtyCount: 2))
    }

    func testWorkstreamStageStyleReviewStageShowsFilledPillWithoutReceding() {
        let style = WorkstreamStageStyle(
            displayStage: .review,
            isManuallySet: false,
            prNumber: 24
        )

        XCTAssertFalse(style.recedesRow)
        XCTAssertEqual(
            style.stagePill,
            WorkstreamStagePillStyle(
                appearance: .filled,
                iconSystemName: "arrow.triangle.pull",
                titleKey: "Review",
                prNumber: 24,
                showsManualMark: false
            )
        )
    }

    func testWorkstreamStageStyleDoneStageShowsOutlinePillAndRecedes() {
        let style = WorkstreamStageStyle(
            displayStage: .done,
            isManuallySet: false,
            prNumber: 24
        )

        XCTAssertTrue(style.recedesRow)
        XCTAssertEqual(
            style.stagePill,
            WorkstreamStagePillStyle(
                appearance: .outline,
                iconSystemName: "checkmark",
                titleKey: "Merged",
                prNumber: 24,
                showsManualMark: false
            )
        )
    }

    func testWorkstreamStageStyleNormalStageShowsNoPillUnlessManual() {
        XCTAssertNil(WorkstreamStageStyle(displayStage: .normal, isManuallySet: false, prNumber: nil).stagePill)

        XCTAssertEqual(
            WorkstreamStageStyle(displayStage: .normal, isManuallySet: true, prNumber: nil).stagePill,
            WorkstreamStagePillStyle(
                appearance: .bare,
                iconSystemName: nil,
                titleKey: "Working",
                prNumber: nil,
                showsManualMark: true
            )
        )
    }

    func testWorkstreamStageStyleManualDoneUsesDoneLabelAndManualMark() {
        let style = WorkstreamStageStyle(
            displayStage: .done,
            isManuallySet: true,
            prNumber: nil
        )

        XCTAssertEqual(style.stagePill?.titleKey, "Done")
        XCTAssertEqual(style.stagePill?.showsManualMark, true)
    }

    func testSidebarModePersistenceRoundTripsAndKeepsLastVisibleMode() {
        SidebarMode.save(.collapsed, defaults: defaults)
        SidebarMode.save(.hidden, defaults: defaults)

        XCTAssertEqual(SidebarMode.load(defaults: defaults), .hidden)
        XCTAssertEqual(SidebarMode.loadLastVisible(defaults: defaults), .collapsed)

        SidebarMode.save(.expanded, defaults: defaults)

        XCTAssertEqual(SidebarMode.load(defaults: defaults), .expanded)
        XCTAssertEqual(SidebarMode.loadLastVisible(defaults: defaults), .expanded)
    }
}
