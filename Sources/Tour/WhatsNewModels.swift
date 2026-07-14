// ABOUTME: Data model for the What's New panel: per-release entries with optional
// ABOUTME: links to tour flows ("Show me").

import Foundation

struct WhatsNewEntry {
    /// SF Symbol name shown next to the entry.
    let symbol: String
    let titleKey: String
    let bodyKey: String
    /// When set, the entry shows a "Show Me" button that starts this tour flow.
    /// The `= nil` default is required: catalog entries omit it via the memberwise init.
    var tourFlowID: String? = nil
}

struct WhatsNewRelease {
    /// Marketing version, e.g. "0.3.0". Must match the release being cut.
    let version: String
    let entries: [WhatsNewEntry]
}
