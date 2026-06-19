// ABOUTME: Tests modifier-state reduction and exact shortcut badge matching.
// ABOUTME: Keeps event-monitor plumbing separate from deterministic hint behavior.

import AppKit
@testable import Dockyard
import XCTest

@MainActor
final class ShortcutHintsTests: XCTestCase {
    func testCommandActivatesHints() {
        let state = ShortcutHintState.reduce(flags: [.command], enabled: true)

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.activeModifiers, [.command])
    }

    func testReducerNormalizesSupportedModifiers() {
        let commandShift = ShortcutHintState.reduce(
            flags: [.command, .shift, .capsLock],
            enabled: true
        )
        let commandOption = ShortcutHintState.reduce(
            flags: [.command, .option, .control],
            enabled: true
        )

        XCTAssertEqual(commandShift.activeModifiers, [.command, .shift])
        XCTAssertEqual(commandOption.activeModifiers, [.command, .option])
    }

    func testReducerRequiresCommand() {
        let state = ShortcutHintState.reduce(flags: [.shift], enabled: true)

        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.activeModifiers, [.shift])
    }

    func testReducerRequiresEnabledSetting() {
        let state = ShortcutHintState.reduce(flags: [.command], enabled: false)

        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.activeModifiers, [.command])
    }

    func testHintReturnsOnlyExactModifierVariant() {
        let hint = ShortcutHint(command: "R", commandShift: "R")

        XCTAssertEqual(
            hint.badge(for: [.command]),
            KeyBadge(key: "R", modifiers: [.command])
        )
        XCTAssertEqual(
            hint.badge(for: [.command, .shift]),
            KeyBadge(key: "R", modifiers: [.command, .shift])
        )
        XCTAssertNil(hint.badge(for: [.command, .option]))
    }
}
