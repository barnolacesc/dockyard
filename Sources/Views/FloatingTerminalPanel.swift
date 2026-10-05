// ABOUTME: Native floating NSPanel and trigger button for Dockyard's persistent global terminal.
// ABOUTME: Backed by macOS WindowServer for 120fps hardware-accelerated dragging, live resizing, and state persistence.

import AppKit
import Combine
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

/// An AppKit NSView bridge that routes title-bar mouse drags directly to the macOS WindowServer at 120fps.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context _: Context) -> DragView {
        DragView()
    }

    func updateNSView(_: DragView, context _: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// An individual tab button within the floating terminal title bar.
private struct GlobalTerminalTabButton: View {
    let title: String
    let isActive: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DesignSpacing.xs) {
            HStack(spacing: DesignSpacing.xs) {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)

                Text(title)
                    .font(.system(size: 11, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .opacity(isHovering || isActive ? 1 : 0)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Tab")
                .help(Text("Close Tab") + Text(" (⌘W)"))
            }
        }
        .padding(.horizontal, DesignSpacing.sm)
        .frame(height: 24)
        .background(
            isActive ? Color.accentColor.opacity(0.15) : (isHovering ? Color.primary.opacity(0.06) : Color.clear),
            in: RoundedRectangle(cornerRadius: DesignRadius.sm)
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignRadius.sm))
        .onHover { isHovering = $0 }
    }
}

/// The content view hosted inside the native floating GlobalTerminalPanel NSPanel.
struct FloatingTerminalPanel: View {
    @ObservedObject var state: GlobalTerminalState
    let onClose: () -> Void
    let onMinimize: () -> Void

    @EnvironmentObject var surfaceCache: TerminalSurfaceCache

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            if let activeID = state.activeTabID {
                SingleTerminalView(
                    surfaceID: activeID,
                    workstreamID: GlobalTerminalState.globalWorkstreamID,
                    workingDirectory: state.workingDirectory,
                    command: nil,
                    initialInput: nil,
                    consumesInitialPrompt: false,
                    isFocused: true,
                    environmentVars: [:]
                )
                .id(activeID)
            } else {
                Color.clear
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Global Terminal")
    }

    private var titleBar: some View {
        ZStack {
            WindowDragHandle()

            HStack(spacing: DesignSpacing.xs) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSpacing.xxs) {
                        ForEach(Array(state.tabs.enumerated()), id: \.element) { index, tabID in
                            let isActive = tabID == state.activeTabID
                            GlobalTerminalTabButton(
                                title: state.tabs.count == 1 ? NSLocalizedString("Global Terminal", comment: "") : "\(NSLocalizedString("Terminal", comment: "")) \(index + 1)",
                                isActive: isActive,
                                canClose: state.tabs.count > 1,
                                onSelect: {
                                    state.selectTab(tabID, surfaceCache: surfaceCache)
                                },
                                onClose: {
                                    state.closeTab(tabID, surfaceCache: surfaceCache)
                                }
                            )
                        }

                        Button(action: {
                            state.addNewTab(surfaceCache: surfaceCache)
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .hoverHighlight(radius: DesignRadius.sm)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Tab")
                        .help(Text("New Tab") + Text(" (⌘T)"))
                    }
                }
                .scrollClipDisabled()

                Spacer(minLength: DesignSpacing.md)

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
            .padding(.horizontal, DesignSpacing.lg)
        }
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }
}

/// A specialized NSPanel that can become key to accept keyboard input in the terminal.
final class GlobalTerminalPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        hideTrafficLights()
    }

    func hideTrafficLights() {
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = super.standardWindowButton(buttonType) {
                button.isHidden = true
                button.removeFromSuperview()
            }
        }
    }

    override func standardWindowButton(_: NSWindow.ButtonType) -> NSButton? {
        nil
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers ?? ""

            // Cmd+T: New Tab
            if flags == .command && chars == "t" {
                GlobalTerminalWindowController.shared.addNewTab()
                return true
            }

            // Cmd+W: Close Active Tab
            if flags == .command && chars == "w" {
                GlobalTerminalWindowController.shared.closeActiveTab()
                return true
            }

            // Cmd+Shift+[ or Cmd+{ : Previous Tab
            if (flags == [.command, .shift] && chars == "[") || chars == "{" {
                GlobalTerminalWindowController.shared.selectPreviousTab()
                return true
            }

            // Cmd+Shift+] or Cmd+} : Next Tab
            if (flags == [.command, .shift] && chars == "]") || chars == "}" {
                GlobalTerminalWindowController.shared.selectNextTab()
                return true
            }

            // Cmd+1 ... Cmd+9: Switch to Tab 1..9
            if flags == .command, let num = Int(chars), num >= 1 && num <= 9 {
                GlobalTerminalWindowController.shared.selectTabAtIndex(num - 1)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Coordinates the lifecycle and synchronization of the native floating NSPanel for Dockyard.
@MainActor
final class GlobalTerminalWindowController: NSObject, NSWindowDelegate {
    static let shared = GlobalTerminalWindowController()

    private(set) var panel: GlobalTerminalPanel?
    private var state: GlobalTerminalState?
    private var surfaceCache: TerminalSurfaceCache?
    private var cancellables = Set<AnyCancellable>()

    var isPanelKeyWindow: Bool {
        panel?.isKeyWindow == true
    }

    func addNewTab() {
        guard let state else { return }
        state.addNewTab(surfaceCache: surfaceCache)
    }

    func closeActiveTab() {
        guard let state else { return }
        state.closeActiveTab(surfaceCache: surfaceCache)
    }

    func selectNextTab() {
        guard let state else { return }
        state.selectNextTab(surfaceCache: surfaceCache)
    }

    func selectPreviousTab() {
        guard let state else { return }
        state.selectPreviousTab(surfaceCache: surfaceCache)
    }

    func selectTabAtIndex(_ index: Int) {
        guard let state else { return }
        state.selectTabAtIndex(index, surfaceCache: surfaceCache)
    }

    func setup(state: GlobalTerminalState, surfaceCache: TerminalSurfaceCache) {
        self.state = state
        self.surfaceCache = surfaceCache

        cancellables.removeAll()

        Publishers.CombineLatest3(state.$isOpen, state.$isMinimized, state.$activeTabID)
            .receive(on: RunLoop.main)
            .sink { [weak self] isOpen, isMinimized, activeTabID in
                self?.syncWindowState(isOpen: isOpen, isMinimized: isMinimized, activeTabID: activeTabID)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleTerminal)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isPanelKeyWindow else { return }
                self.addNewTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .closeTerminal)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isPanelKeyWindow else { return }
                self.closeActiveTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .prevTab)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isPanelKeyWindow else { return }
                self.selectPreviousTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .nextTab)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isPanelKeyWindow else { return }
                self.selectNextTab()
            }
            .store(in: &cancellables)
    }

    func syncWindowState(isOpen: Bool, isMinimized: Bool, activeTabID: UUID?) {
        guard let state, let surfaceCache else { return }

        if isOpen, !isMinimized, activeTabID != nil {
            showPanel(state: state, surfaceCache: surfaceCache)
        } else {
            hidePanel()
        }
    }

    private func showPanel(state: GlobalTerminalState, surfaceCache: TerminalSurfaceCache) {
        if panel == nil {
            createPanel(state: state, surfaceCache: surfaceCache)
        }

        guard let panel else { return }
        if let activeTabID = state.activeTabID {
            surfaceCache.setSurfaceAlwaysVisible(activeTabID, isAlwaysVisible: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func createPanel(state: GlobalTerminalState, surfaceCache: TerminalSurfaceCache) {
        let initialSize = state.size ?? CGSize(
            width: GlobalTerminalState.defaultWidth,
            height: GlobalTerminalState.defaultHeight
        )

        var targetRect = NSRect(origin: .zero, size: initialSize)
        if let savedPos = state.position {
            targetRect.origin = savedPos
        }

        // Validate whether targetRect is on a visible screen:
        let isVisibleOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(targetRect)
        }

        if !isVisibleOnScreen || state.position == nil {
            if let mainWindow = NSApp.mainWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) }) {
                let mainFrame = mainWindow.frame
                let x = max(mainFrame.minX + 24, mainFrame.maxX - initialSize.width - 24)
                let y = max(mainFrame.minY + 24, mainFrame.minY + 48)
                targetRect.origin = CGPoint(x: x, y: y)
            } else if let screen = NSScreen.main ?? NSScreen.screens.first {
                let screenRect = screen.visibleFrame
                let x = screenRect.maxX - initialSize.width - 24
                let y = screenRect.minY + 48
                targetRect.origin = CGPoint(x: x, y: y)
            } else {
                targetRect.origin = CGPoint(x: 100, y: 100)
            }
        }

        let panel = GlobalTerminalPanel(
            contentRect: targetRect,
            styleMask: [
                .titled,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: GlobalTerminalState.minWidth, height: GlobalTerminalState.minHeight)
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.delegate = self

        panel.hideTrafficLights()

        let contentView = FloatingTerminalPanel(
            state: state,
            onClose: { [weak self, weak state] in
                guard let state, let self else { return }
                state.close(surfaceCache: self.surfaceCache)
            },
            onMinimize: { [weak self, weak state] in
                guard let state, let self else { return }
                state.minimize(surfaceCache: self.surfaceCache)
            }
        )
        .environmentObject(surfaceCache)

        panel.contentView = NSHostingView(rootView: contentView)
        self.panel = panel
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_: Notification) {
        guard let panel else { return }
        state?.savePosition(panel.frame.origin)
    }

    func windowDidResize(_: Notification) {
        guard let panel else { return }
        state?.saveSize(panel.frame.size)
        state?.savePosition(panel.frame.origin)
    }

    func windowWillClose(_: Notification) {
        guard let state, let surfaceCache else { return }
        state.close(surfaceCache: surfaceCache)
    }
}
