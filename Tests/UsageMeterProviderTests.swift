// ABOUTME: Tests for usage meter provider selection and cycling.
// ABOUTME: Keeps sidebar usage meter routing deterministic across agent changes.

@testable import Dockyard
import XCTest

final class UsageMeterProviderTests: XCTestCase {
    func testPreferredProviderMapsSupportedCodingCLIs() {
        XCTAssertEqual(UsageMeterProvider.preferred(for: .claude), .claude)
        XCTAssertEqual(UsageMeterProvider.preferred(for: .codex), .codex)
        XCTAssertNil(UsageMeterProvider.preferred(for: .opencode))
        XCTAssertNil(UsageMeterProvider.preferred(for: .gemini))
    }

    func testCyclingWrapsThroughAvailableProviders() {
        let providers: [UsageMeterProvider] = [.claude, .codex]

        XCTAssertEqual(cycledUsageMeterProvider(current: .claude, available: providers, direction: 1), .codex)
        XCTAssertEqual(cycledUsageMeterProvider(current: .codex, available: providers, direction: 1), .claude)
        XCTAssertEqual(cycledUsageMeterProvider(current: .claude, available: providers, direction: -1), .codex)
    }

    func testResolvedSelectionUsesPreferredProviderWhenItChanges() {
        let selection = resolvedUsageMeterProvider(
            current: .claude,
            preferred: .codex,
            previousPreferred: .claude,
            available: [.claude, .codex]
        )

        XCTAssertEqual(selection, .codex)
    }

    func testResolvedSelectionKeepsManualSelectionWhenPreferredDoesNotChange() {
        let selection = resolvedUsageMeterProvider(
            current: .codex,
            preferred: .claude,
            previousPreferred: .claude,
            available: [.claude, .codex]
        )

        XCTAssertEqual(selection, .codex)
    }

    func testResolvedSelectionFallsBackWhenCurrentUnavailable() {
        let selection = resolvedUsageMeterProvider(
            current: .codex,
            preferred: .claude,
            previousPreferred: .claude,
            available: [.claude]
        )

        XCTAssertEqual(selection, .claude)
    }

    func testDisplayStateShowsDataWhenSelectedProviderHasData() {
        XCTAssertEqual(usageMeterDisplayState(selectedHasData: true, providerCount: 1), .data)
        XCTAssertEqual(usageMeterDisplayState(selectedHasData: true, providerCount: 2), .data)
    }

    func testDisplayStateKeepsSwitcherVisibleWhenSelectedProviderHasNoDataButOthersExist() {
        // Regression: switching to a provider with no data yet must not hide the switcher,
        // otherwise the user is stranded and cannot switch back.
        XCTAssertEqual(usageMeterDisplayState(selectedHasData: false, providerCount: 2), .placeholder)
    }

    func testDisplayStateHiddenWhenNoDataAndOnlyOneProvider() {
        XCTAssertEqual(usageMeterDisplayState(selectedHasData: false, providerCount: 1), .hidden)
    }
}
