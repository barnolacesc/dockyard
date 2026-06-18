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
}
