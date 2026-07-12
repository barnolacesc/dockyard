// ABOUTME: Anchor-preference plumbing that lets views register as tour targets.
// ABOUTME: Mirrors the ShortcutHints pattern; overlay reads the anchors at the root.

import SwiftUI

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourAnchorID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TourAnchorID: Anchor<CGRect>],
        nextValue: () -> [TourAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Registers this view as a tour target. `enabled` gates registration
    /// without changing view identity (used by per-row anchors so only the
    /// selected project row registers).
    func tourAnchor(_ id: TourAnchorID?, enabled: Bool = true) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { anchor in
            guard let id, enabled else { return [:] }
            return [id: anchor]
        }
    }
}
