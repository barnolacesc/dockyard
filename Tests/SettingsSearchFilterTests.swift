// ABOUTME: Unit tests for Settings search filtering logic.
// ABOUTME: Verifies title, option, caption, keyword, section, case-insensitivity, and clear actions.

@testable import Dockyard
import XCTest

final class SettingsSearchFilterTests: XCTestCase {
    func testEmptyQueryMatchesAllSectionsAndItems() {
        let filter = SettingsFilter(query: "")
        XCTAssertFalse(filter.isSearching)
        XCTAssertTrue(filter.hasMatches)

        for section in SettingsSectionID.allCases {
            XCTAssertTrue(filter.matches(section: section), "Section \(section) should match empty query")
        }

        for item in SettingsItemID.allCases {
            XCTAssertTrue(filter.matches(item: item), "Item \(item) should match empty query")
        }
    }

    func testWhitespaceQueryMatchesAll() {
        let filter = SettingsFilter(query: "   \t\n  ")
        XCTAssertFalse(filter.isSearching)
        XCTAssertTrue(filter.hasMatches)

        XCTAssertTrue(filter.matches(section: .general))
        XCTAssertTrue(filter.matches(item: .generalBaseDirectory))
    }

    func testCaseInsensitiveMatching() {
        let queries = ["tmux", "TMUX", "TmUx", "  tmux  "]
        for query in queries {
            let filter = SettingsFilter(query: query)
            XCTAssertTrue(filter.isSearching)
            XCTAssertTrue(filter.hasMatches)

            XCTAssertTrue(filter.matches(item: .envToolTmux), "Failed for query: \(query)")
            XCTAssertTrue(filter.matches(item: .agentTmuxMode), "Failed for query: \(query)")
            XCTAssertTrue(filter.matches(section: .environment), "Failed for query: \(query)")
            XCTAssertTrue(filter.matches(section: .codingAgent), "Failed for query: \(query)")

            // Other sections should be hidden
            XCTAssertFalse(filter.matches(section: .general), "General should not match tmux")
            XCTAssertFalse(filter.matches(section: .power), "Power should not match tmux")
            XCTAssertFalse(filter.matches(section: .updates), "Updates should not match tmux")
            XCTAssertFalse(filter.matches(section: .advanced), "Advanced should not match tmux")
        }
    }

    func testCaffeinateKeywordMatchesPowerSection() {
        let filter = SettingsFilter(query: "caffeinate")
        XCTAssertTrue(filter.isSearching)
        XCTAssertTrue(filter.hasMatches)

        XCTAssertTrue(filter.matches(section: .power))
        XCTAssertTrue(filter.matches(item: .powerKeepAwake))

        XCTAssertFalse(filter.matches(section: .environment))
        XCTAssertFalse(filter.matches(section: .general))
        XCTAssertFalse(filter.matches(section: .updates))
        XCTAssertFalse(filter.matches(section: .advanced))
    }

    func testBypassKeywordMatchesPermissionsAndWrites() {
        let filter = SettingsFilter(query: "bypass")
        XCTAssertTrue(filter.isSearching)
        XCTAssertTrue(filter.hasMatches)

        XCTAssertTrue(filter.matches(section: .codingAgent))
        XCTAssertTrue(filter.matches(item: .agentDangerousPermissions))
        XCTAssertTrue(filter.matches(item: .agentAllowOutsideWorktree))

        XCTAssertFalse(filter.matches(section: .power))
        XCTAssertFalse(filter.matches(section: .updates))
    }

    func testPromptKeywordMatchesPromptsAndNotifications() {
        let filter = SettingsFilter(query: "prompt")
        XCTAssertTrue(filter.isSearching)
        XCTAssertTrue(filter.hasMatches)

        // Matches auto-rename prompt and confirm quit prompt
        XCTAssertTrue(filter.matches(item: .agentAutoRenameBranch))
        XCTAssertTrue(filter.matches(item: .generalConfirmQuit))
        XCTAssertTrue(filter.matches(item: .updatesAutomaticChecks))
    }

    func testChannelKeywordMatchesReleaseChannel() {
        let filter = SettingsFilter(query: "channel")
        XCTAssertTrue(filter.isSearching)
        XCTAssertTrue(filter.hasMatches)

        XCTAssertTrue(filter.matches(section: .updates))
        XCTAssertTrue(filter.matches(item: .updatesChannel))

        XCTAssertFalse(filter.matches(section: .power))
    }

    func testSettingTitlesMatch() {
        let expectations: [(String, SettingsItemID, SettingsSectionID)] = [
            ("Base directory", .generalBaseDirectory, .general),
            ("Branch prefix", .generalBranchPrefix, .general),
            ("Symlink .env files", .generalSymlinkEnv, .general),
            ("Editor command", .generalEditorCommand, .general),
            ("Theme", .generalTheme, .general),
            ("Language", .generalLanguage, .general),
            ("Show shortcut hints", .generalShortcutHints, .general),
            ("Confirm before quitting", .generalConfirmQuit, .general),
            ("Launch at login", .generalLaunchAtLogin, .general),
            ("Keep Mac awake", .powerKeepAwake, .power),
            ("Release channel", .updatesChannel, .updates),
            ("Automatically check for updates", .updatesAutomaticChecks, .updates),
            ("Check now", .updatesCheckNow, .updates),
            ("Coding CLI", .agentCodingCLI, .codingAgent),
            ("Dangerously skip permissions", .agentDangerousPermissions, .codingAgent),
            ("Allow writes outside worktree", .agentAllowOutsideWorktree, .codingAgent),
            ("Agent Teams", .agentTeams, .codingAgent),
            ("Auto-rename branch", .agentAutoRenameBranch, .codingAgent),
            ("Claude usage plan", .agentClaudeUsagePlan, .codingAgent),
            ("External Terminal", .agentExternalTerminal, .codingAgent),
            ("Open links in", .agentOpenLinksIn, .codingAgent),
            ("External Browser", .agentExternalBrowser, .codingAgent),
            ("Detailed logging", .advancedDetailedLogging, .advanced),
            ("Quick action debug", .advancedQuickActionDebug, .advanced),
            ("Clear project list", .advancedClearProjects, .advanced),
        ]

        for (query, item, section) in expectations {
            let filter = SettingsFilter(query: query)
            XCTAssertTrue(filter.matches(item: item), "Query '\(query)' should match item \(item)")
            XCTAssertTrue(filter.matches(section: section), "Query '\(query)' should match section \(section)")
        }
    }

    func testOptionLabelsMatch() {
        let filterDark = SettingsFilter(query: "Dark")
        XCTAssertTrue(filterDark.matches(item: .generalTheme))

        let filterPreRelease = SettingsFilter(query: "Pre-releases")
        XCTAssertTrue(filterPreRelease.matches(item: .updatesChannel))

        let filterInternalTab = SettingsFilter(query: "Internal Tab")
        XCTAssertTrue(filterInternalTab.matches(item: .agentOpenLinksIn))

        let filterEnterprise = SettingsFilter(query: "Enterprise")
        XCTAssertTrue(filterEnterprise.matches(item: .agentClaudeUsagePlan))

        let filterGhostty = SettingsFilter(query: "Ghostty")
        XCTAssertTrue(filterGhostty.matches(item: .agentExternalTerminal))

        let filterSafari = SettingsFilter(query: "Safari")
        XCTAssertTrue(filterSafari.matches(item: .agentExternalBrowser))
    }

    func testDescriptionsAndCaptionsMatch() {
        let filterRestart = SettingsFilter(query: "Restart the app")
        XCTAssertTrue(filterRestart.matches(item: .generalLanguage))

        let filterSparkle = SettingsFilter(query: "Sparkle checks daily")
        XCTAssertTrue(filterSparkle.matches(item: .updatesAutomaticChecks))

        let filterOutside = SettingsFilter(query: "modify files anywhere on disk")
        XCTAssertTrue(filterOutside.matches(item: .agentAllowOutsideWorktree))

        let filterSandboxing = SettingsFilter(query: "sandboxing")
        XCTAssertTrue(filterSandboxing.matches(item: .agentDangerousPermissions))
    }

    func testSectionTitleMatchShowsAllItemsInSection() {
        let filterPower = SettingsFilter(query: "Power")
        XCTAssertTrue(filterPower.matches(section: .power))
        XCTAssertTrue(filterPower.matches(item: .powerKeepAwake))

        let filterAdvanced = SettingsFilter(query: "Advanced")
        XCTAssertTrue(filterAdvanced.matches(section: .advanced))
        XCTAssertTrue(filterAdvanced.matches(item: .advancedDetailedLogging))
        XCTAssertTrue(filterAdvanced.matches(item: .advancedQuickActionDebug))
        XCTAssertTrue(filterAdvanced.matches(item: .advancedClearProjects))

        let filterGeneral = SettingsFilter(query: "General")
        XCTAssertTrue(filterGeneral.matches(section: .general))
        XCTAssertTrue(filterGeneral.matches(item: .generalBaseDirectory))
        XCTAssertTrue(filterGeneral.matches(item: .generalTheme))
        XCTAssertTrue(filterGeneral.matches(item: .generalConfirmQuit))
    }

    func testMultiWordQueryMatching() {
        let filterKeepAwake = SettingsFilter(query: "keep awake")
        XCTAssertTrue(filterKeepAwake.matches(item: .powerKeepAwake))

        let filterDangerSkip = SettingsFilter(query: "danger skip")
        XCTAssertTrue(filterDangerSkip.matches(item: .agentDangerousPermissions))

        let filterClearList = SettingsFilter(query: "clear list")
        XCTAssertTrue(filterClearList.matches(item: .advancedClearProjects))

        let filterOpenLinks = SettingsFilter(query: "open links")
        XCTAssertTrue(filterOpenLinks.matches(item: .agentOpenLinksIn))
    }

    func testNoMatchesAndClearSearchRestoresAll() {
        var filter = SettingsFilter(query: "xyznonexistent999abc")
        XCTAssertTrue(filter.isSearching)
        XCTAssertFalse(filter.hasMatches)

        for section in SettingsSectionID.allCases {
            XCTAssertFalse(filter.matches(section: section))
        }
        for item in SettingsItemID.allCases {
            XCTAssertFalse(filter.matches(item: item))
        }

        // Clear search
        filter.query = ""
        XCTAssertFalse(filter.isSearching)
        XCTAssertTrue(filter.hasMatches)

        for section in SettingsSectionID.allCases {
            XCTAssertTrue(filter.matches(section: section))
        }
        for item in SettingsItemID.allCases {
            XCTAssertTrue(filter.matches(item: item))
        }
    }

    func testCatalanKeywordsMatch() {
        let filterEntorn = SettingsFilter(query: "Entorn")
        XCTAssertTrue(filterEntorn.matches(section: .environment))

        let filterEnergia = SettingsFilter(query: "Energia")
        XCTAssertTrue(filterEnergia.matches(section: .power))

        let filterAvancat = SettingsFilter(query: "Avançat")
        XCTAssertTrue(filterAvancat.matches(section: .advanced))

        let filterIdioma = SettingsFilter(query: "idioma")
        XCTAssertTrue(filterIdioma.matches(item: .generalLanguage))

        let filterFosc = SettingsFilter(query: "Fosc")
        XCTAssertTrue(filterFosc.matches(item: .generalTheme))

        let filterDreceres = SettingsFilter(query: "dreceres")
        XCTAssertTrue(filterDreceres.matches(item: .generalShortcutHints))
    }

    func testToolRowsMatchIndividualTools() {
        let tools: [(String, SettingsItemID)] = [
            ("claude", .envToolClaude),
            ("codex", .envToolCodex),
            ("opencode", .envToolOpencode),
            ("agy", .envToolAgy),
            ("pi", .envToolPi),
            ("terminal-browser", .envToolTerminalBrowser),
            ("gh", .envToolGh),
            ("git", .envToolGit),
        ]

        for (name, item) in tools {
            let filter = SettingsFilter(query: name)
            XCTAssertTrue(filter.matches(item: item), "Query '\(name)' should match \(item)")
            XCTAssertTrue(filter.matches(section: .environment), "Query '\(name)' should keep Environment visible")
        }
    }
}
