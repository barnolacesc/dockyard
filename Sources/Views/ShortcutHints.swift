// ABOUTME: Observes Command modifier state and renders contextual shortcut badges.
// ABOUTME: Uses anchor preferences so badges track visible SwiftUI controls without intercepting input.

import AppKit
import SwiftUI

struct ShortcutHintState: Equatable {
    let isActive: Bool
    let activeModifiers: NSEvent.ModifierFlags

    static func reduce(flags: NSEvent.ModifierFlags, enabled: Bool) -> Self {
        let normalized = flags.intersection([.command, .shift, .option])
        return Self(
            isActive: enabled && normalized.contains(.command),
            activeModifiers: normalized
        )
    }
}

struct KeyBadge: Equatable {
    let key: String
    let modifiers: NSEvent.ModifierFlags
}

struct ShortcutHint {
    private let badges: [UInt: KeyBadge]

    init(
        command: String? = nil,
        commandShift: String? = nil,
        commandOption: String? = nil
    ) {
        var badges: [UInt: KeyBadge] = [:]
        if let command {
            badges[NSEvent.ModifierFlags.command.rawValue] = KeyBadge(key: command, modifiers: [.command])
        }
        if let commandShift {
            let modifiers: NSEvent.ModifierFlags = [.command, .shift]
            badges[modifiers.rawValue] = KeyBadge(key: commandShift, modifiers: modifiers)
        }
        if let commandOption {
            let modifiers: NSEvent.ModifierFlags = [.command, .option]
            badges[modifiers.rawValue] = KeyBadge(key: commandOption, modifiers: modifiers)
        }
        self.badges = badges
    }

    func badge(for modifiers: NSEvent.ModifierFlags) -> KeyBadge? {
        badges[modifiers.intersection([.command, .shift, .option]).rawValue]
    }
}

@MainActor
final class ShortcutHintController: ObservableObject {
    static let shared = ShortcutHintController()

    @Published private(set) var isActive = false
    @Published private(set) var activeModifiers: NSEvent.ModifierFlags = []

    private var enabled: Bool
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        enabled = defaults.object(forKey: "dockyard.showShortcutHints") as? Bool ?? true
    }

    func start() {
        guard flagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.apply(flags: event.modifierFlags)
            return event
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.dismiss()
            return event
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        apply(flags: NSEvent.modifierFlags)
    }

    func stop() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
        dismiss()
    }

    private func apply(flags: NSEvent.ModifierFlags) {
        let state = ShortcutHintState.reduce(flags: flags, enabled: enabled)
        isActive = state.isActive
        activeModifiers = state.activeModifiers
    }

    private func dismiss() {
        isActive = false
    }
}

private struct ShortcutHintAnchor {
    let id: UUID
    let anchor: Anchor<CGRect>
    let hint: ShortcutHint
}

private struct ShortcutHintAnchorKey: PreferenceKey {
    static let defaultValue: [UUID: ShortcutHintAnchor] = [:]

    static func reduce(
        value: inout [UUID: ShortcutHintAnchor],
        nextValue: () -> [UUID: ShortcutHintAnchor]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ShortcutHintModifier: ViewModifier {
    let hint: ShortcutHint
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content.anchorPreference(key: ShortcutHintAnchorKey.self, value: .bounds) { anchor in
            [id: ShortcutHintAnchor(id: id, anchor: anchor, hint: hint)]
        }
    }
}

private struct ShortcutHintOverlayModifier: ViewModifier {
    @EnvironmentObject private var controller: ShortcutHintController

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ShortcutHintAnchorKey.self) { entries in
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    if controller.isActive {
                        ForEach(Array(entries.values), id: \.id) { entry in
                            if let badge = entry.hint.badge(for: controller.activeModifiers) {
                                let rect = proxy[entry.anchor]
                                HintBadge(badge: badge)
                                    .frame(width: rect.width, height: rect.height, alignment: .topTrailing)
                                    .offset(x: rect.minX + 4, y: rect.minY - 4)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.1), value: controller.isActive)
                .animation(.easeOut(duration: 0.1), value: controller.activeModifiers.rawValue)
            }
        }
    }
}

private struct HintBadge: View {
    let badge: KeyBadge

    var body: some View {
        HStack(spacing: 2) {
            if badge.modifiers.contains(.command) {
                Image(systemName: "command")
            }
            if badge.modifiers.contains(.option) {
                Image(systemName: "option")
            }
            if badge.modifiers.contains(.shift) {
                Image(systemName: "shift")
            }
            Text(badge.key)
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.primary)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

extension View {
    func shortcutHint(_ hint: ShortcutHint) -> some View {
        modifier(ShortcutHintModifier(hint: hint))
    }

    func shortcutHintOverlay() -> some View {
        modifier(ShortcutHintOverlayModifier())
    }
}
