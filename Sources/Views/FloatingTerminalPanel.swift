// ABOUTME: Floating panel and trigger button for Dockyard's persistent global terminal.
// ABOUTME: Draggable title bar, window-bound clamping, and minimize/close actions.

import AppKit
import SwiftUI

/// A floating circular button positioned at the bottom-right corner to toggle the global terminal.
struct GlobalTerminalButton: View {
    @ObservedObject var state: GlobalTerminalState
    let onToggle: () -> Void

    @State private var isHovering = false

    private var isActive: Bool {
        state.isOpen && !state.isMinimized
    }

    private var accessibilityLabelKey: LocalizedStringKey {
        if !state.isOpen {
            return "Open Global Terminal"
        } else if state.isMinimized {
            return "Restore Global Terminal"
        } else {
            return "Minimize Global Terminal"
        }
    }

    /// The content and behavior of the global terminal trigger button.
    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isActive ? "terminal.fill" : "terminal")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : (isHovering ? .primary : .secondary))
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isHovering ? 0.2 : 0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .pressable()
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabelKey)
        .accessibilityHint("Toggles the persistent floating global terminal")
        .help(accessibilityLabelKey)
    }
}

/// A floating, draggable panel hosting the persistent global terminal instance.
struct FloatingTerminalPanel: View {
    let surfaceID: UUID
    let windowSize: CGSize
    @ObservedObject var state: GlobalTerminalState
    let onClose: () -> Void
    let onMinimize: () -> Void

    @State private var dragStartPosition: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Effective size of the panel clamped to the host window size.
    private var effectiveSize: CGSize {
        GlobalTerminalState.effectivePanelSize(windowSize: windowSize)
    }

    /// Current top-left position of the panel clamped within the host window bounds.
    private var currentPosition: CGPoint {
        let defaultPos = GlobalTerminalState.defaultPosition(panelSize: effectiveSize, windowSize: windowSize)
        let pos = state.position ?? defaultPos
        return GlobalTerminalState.clampedPosition(pos, panelSize: effectiveSize, windowSize: windowSize)
    }

    /// The content and layout of the floating terminal panel.
    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            terminalContent
        }
        .frame(width: effectiveSize.width, height: effectiveSize.height)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95), in: RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .offset(x: currentPosition.x, y: currentPosition.y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Global Terminal")
        .onChange(of: windowSize) { _, newSize in
            let newEffectiveSize = GlobalTerminalState.effectivePanelSize(windowSize: newSize)
            let reclamped = GlobalTerminalState.clampedPosition(currentPosition, panelSize: newEffectiveSize, windowSize: newSize)
            if state.position != reclamped {
                state.savePosition(reclamped)
            }
        }
    }

    /// The draggable title bar with label, minimize, and close actions.
    private var titleBar: some View {
        HStack(spacing: DesignSpacing.sm) {
            HStack(spacing: DesignSpacing.xs) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Global Terminal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)

            HStack(spacing: DesignSpacing.xs) {
                Button(action: onMinimize) {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .hoverHighlight(radius: DesignRadius.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimize Global Terminal")
                .help("Minimize")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .hoverHighlight(radius: DesignRadius.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Global Terminal")
                .help("Close")
            }
        }
        .padding(.horizontal, DesignSpacing.md)
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
    }

    /// Drag gesture handler that tracks panel movement and clamps position within window bounds.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                let start = dragStartPosition ?? currentPosition
                if dragStartPosition == nil {
                    dragStartPosition = start
                }
                let target = CGPoint(
                    x: start.x + gesture.translation.width,
                    y: start.y + gesture.translation.height
                )
                let clamped = GlobalTerminalState.clampedPosition(target, panelSize: effectiveSize, windowSize: windowSize)
                state.position = clamped
            }
            .onEnded { _ in
                if let finalPos = state.position {
                    let clamped = GlobalTerminalState.clampedPosition(finalPos, panelSize: effectiveSize, windowSize: windowSize)
                    state.savePosition(clamped)
                }
                dragStartPosition = nil
            }
    }

    /// The terminal view hosting the Ghostty surface in the user's home directory.
    private var terminalContent: some View {
        SingleTerminalView(
            surfaceID: surfaceID,
            workstreamID: GlobalTerminalState.globalWorkstreamID,
            workingDirectory: state.workingDirectory,
            command: nil,
            initialInput: nil,
            consumesInitialPrompt: false,
            isFocused: true,
            environmentVars: [:]
        )
    }
}
