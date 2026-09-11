// ABOUTME: Locks the versioned Coding Agent capability contract to proven behavior.
// ABOUTME: Prevents UI and command gates from claiming unsupported CLI features.

@testable import Dockyard
import XCTest

final class CodingAgentCapabilitiesTests: XCTestCase {
    func testContractVersionIsThree() {
        XCTAssertEqual(CodingAgentCapabilities.contractVersion, 3)
    }

    func testClaudeCapabilitiesMatchSpecializedAdapter() {
        XCTAssertEqual(
            CodingCLI.claude.capabilities,
            CodingAgentCapabilities(
                commandStrategy: .claude,
                stateReportingStrategy: .claudeHooks,
                supportsDirectLaunch: true,
                supportsCLISessionResume: true,
                supportsDockyardTmuxPersistence: true,
                reportsMainAgentState: true,
                reportsSubagentState: true,
                supportsDangerousPermissionBypass: true,
                supportsLivePermissionControl: true,
                supportsAutoRenameBranch: true,
                supportsAgentTeams: true
            )
        )
    }

    func testCodexCapabilitiesMatchSpecializedAdapter() {
        XCTAssertEqual(
            CodingCLI.codex.capabilities,
            CodingAgentCapabilities(
                commandStrategy: .codex,
                stateReportingStrategy: .codexHooks,
                supportsDirectLaunch: true,
                supportsCLISessionResume: true,
                supportsDockyardTmuxPersistence: true,
                reportsMainAgentState: true,
                reportsSubagentState: false,
                supportsDangerousPermissionBypass: true,
                supportsLivePermissionControl: true,
                supportsAutoRenameBranch: true,
                supportsAgentTeams: false
            )
        )
    }

    func testOpenCodeCapabilitiesIncludeAutoRenameInstructions() {
        XCTAssertTrue(CodingCLI.opencode.supportsAutoRenameBranch)
        XCTAssertEqual(CodingCLI.opencode.capabilities.commandStrategy, .generic)
    }

    func testGeminiCapabilitiesDoNotClaimAutoRename() {
        XCTAssertFalse(CodingCLI.gemini.supportsAutoRenameBranch)
        XCTAssertEqual(CodingCLI.gemini.capabilities.commandStrategy, .generic)
    }

    func testOnlyClaudeClaimsSubagentStatus() {
        XCTAssertTrue(CodingCLI.claude.capabilities.reportsSubagentState)
        XCTAssertTrue([CodingCLI.codex, .opencode, .gemini].allSatisfy {
            !$0.capabilities.reportsSubagentState
        })
    }

    func testMainAgentStatusClaimsHaveAReportingStrategy() {
        for cli in CodingCLI.allCases {
            let capabilities = cli.capabilities
            XCTAssertEqual(
                capabilities.reportsMainAgentState,
                capabilities.stateReportingStrategy != .unavailable
            )
        }
    }

    func testExistingUICompatibilityPropertiesUseCapabilityContract() {
        for cli in CodingCLI.allCases {
            XCTAssertEqual(cli.supportsAgentTeams, cli.capabilities.supportsAgentTeams)
            XCTAssertEqual(cli.supportsAutoRenameBranch, cli.capabilities.supportsAutoRenameBranch)
        }
    }
}
