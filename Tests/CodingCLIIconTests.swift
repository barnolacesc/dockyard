// ABOUTME: Tests for CodingCLI icon assets, brand colors, and image mappings.
// ABOUTME: Verifies all CodingCLI options have corresponding icon assets and valid configurations.

@testable import Dockyard
import SwiftUI
import XCTest

final class CodingCLIIconTests: XCTestCase {
    func testIconAssetNamesForAllCases() {
        XCTAssertEqual(CodingCLI.claude.iconAssetName, "claude")
        XCTAssertEqual(CodingCLI.codex.iconAssetName, "openai")
        XCTAssertEqual(CodingCLI.agy.iconAssetName, "agy")
        XCTAssertEqual(CodingCLI.opencode.iconAssetName, "opencode")
    }

    func testBrandColorsDefinedForAllCases() {
        for cli in CodingCLI.allCases {
            // Ensure brandColor is non-nil/evaluates
            let color = cli.brandColor
            XCTAssertNotNil(color)
        }
    }

    func testAssetFilesExistInBundleOrAssets() {
        let expectedAssets = ["claude", "openai", "agy", "opencode"]
        for assetName in expectedAssets {
            let image = NSImage(named: NSImage.Name(assetName))
            XCTAssertNotNil(image, "Expected to load asset '\(assetName)' from asset catalog")
        }
    }

    func testCodingCLIIconViewInstantiation() {
        for cli in CodingCLI.allCases {
            let icon = CodingCLIIcon(cli: cli, size: 12, useBrandColor: true)
            XCTAssertEqual(icon.cli, cli)
            XCTAssertEqual(icon.size, 12)
            XCTAssertTrue(icon.useBrandColor)
        }
    }
}
