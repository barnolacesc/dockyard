// ABOUTME: Hand-curated What's New content per release, newest first.
// ABOUTME: Authoring rule: every user-facing feature adds an entry to the release being cut.

import Foundation

enum WhatsNewCatalog {
    /// Newest first. The version string must match the release that ships it
    /// (release-please owns version numbers; adjust when the release PR is cut).
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(version: "0.3.0", entries: [
            WhatsNewEntry(
                symbol: "sparkles",
                titleKey: "Interactive Tour",
                bodyKey: "A guided tour walks you through projects, workstreams, and the Coding Agent. Restart it anytime from the Help menu.",
                tourFlowID: GettingStartedFlow.id
            ),
            WhatsNewEntry(
                symbol: "megaphone",
                titleKey: "What's New Panel",
                bodyKey: "After each update, the highlights show up right here."
            ),
        ]),
    ]
}
