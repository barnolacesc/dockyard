// ABOUTME: Drives the canonical unattended Dockyard website product tour.
// ABOUTME: Uses accessibility identifiers and visible-state waits instead of coordinates.

import XCTest

final class DockyardDemoUITests: XCTestCase {
    func testCanonicalWebsiteTour() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo-mode", "--demo-autoplay"]
        app.launchEnvironment["DOCKYARD_DEMO_MODE"] = "1"
        app.launchEnvironment["DOCKYARD_DEMO_AUTOPLAY"] = "1"
        app.launchEnvironment["DOCKYARD_DEMO_ROOT"] = ProcessInfo.processInfo.environment["DOCKYARD_DEMO_ROOT"]
            ?? "/tmp/dockyard-website-demo/fixture"
        app.launchEnvironment["DOCKYARD_DEMO_READY_FILE"] = ProcessInfo.processInfo.environment["DOCKYARD_DEMO_READY_FILE"]
            ?? "/tmp/dockyard-demo-process.pid"
        app.launch()

        XCTAssertTrue(app.staticTexts["Fix short inode detection"].waitForExistence(timeout: 15))
        paced(3)

        app.buttons["workspace-tab-coding-agent"].click()
        XCTAssertTrue(app.staticTexts["✓ 42 tests passed in 1.8s"].waitForExistence(timeout: 8))
        paced(4)

        app.buttons["workspace-tab-info"].click()
        app.typeKey(.return, modifierFlags: [.command, .shift])
        paced(5)

        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(app.buttons["workspace-tab-browser"].waitForExistence(timeout: 8))
        paced(7)

        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.buttons["workspace-tab-editor"].waitForExistence(timeout: 8))
        paced(7)

        app.buttons["workspace-tab-info"].click()
        paced(3)
        if app.buttons["Create PR"].waitForExistence(timeout: 3) {
            app.buttons["Create PR"].click()
            XCTAssertTrue(app.buttons["Pull request #185"].waitForExistence(timeout: 5))
        }
        paced(4)

        app.typeKey("0", modifierFlags: .command)
        // Keep the final overview alive until the independent recorder has finalized.
        paced(20)
    }

    private func paced(_ seconds: UInt32) { sleep(seconds) }
}
