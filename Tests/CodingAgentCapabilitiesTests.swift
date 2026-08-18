// ABOUTME: Locks the versioned Coding Agent capability contract to proven behavior.
// ABOUTME: Prevents UI and command gates from claiming unsupported CLI features.

@testable import Dockyard
import XCTest

final class CodingAgentCapabilitiesTests: XCTestCase {
    func testContractVersionIsTwo() {
        XCTAssertEqual(CodingAgentCapabilities.contractVersion, 2)
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
                supportsAutoRenameBranch: false,
                supportsAgentTeams: false
            )
        )
    }

    func testGenericCLICapabilitiesDoNotClaimSpecializedFeatures() {
        for cli in [CodingCLI.opencode, .gemini] {
            XCTAssertEqual(
                cli.capabilities,
                CodingAgentCapabilities(
                    commandStrategy: .generic,
                    stateReportingStrategy: .unavailable,
                    supportsDirectLaunch: true,
                    supportsCLISessionResume: false,
                    supportsDockyardTmuxPersistence: true,
                    reportsMainAgentState: false,
                    reportsSubagentState: false,
                    supportsDangerousPermissionBypass: false,
                    supportsLivePermissionControl: false,
                    supportsAutoRenameBranch: false,
                    supportsAgentTeams: false
                )
            )
        }
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
