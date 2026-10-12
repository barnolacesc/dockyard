// ABOUTME: Native floating NSPanel and trigger button for Dockyard's persistent global terminal.
// ABOUTME: Backed by macOS WindowServer for 120fps hardware-accelerated dragging, live resizing, and state persistence.

import AppKit
import Combine
import SwiftUI

/// A floating circular button positioned at the bottom-right corner to toggle the global terminal.
struct GlobalTerminalButton: View {
    @ObservedObject var state: GlobalTerminalState
    let onToggle: () -> Void

    var body: some View {
        DraggableGlobalTerminalBubble(state: state, onToggle: onToggle)
    }
}

/// An interactive floating button that can be dragged across the screen and snaps to the borders of the Dockyard app.
struct DraggableGlobalTerminalBubble: View {
    @ObservedObject var state: GlobalTerminalState
    let onToggle: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false

    private let buttonSize: CGFloat = 36
    private let padding: CGFloat = 16

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

    var body: some View {
        GeometryReader { proxy in
            let restingOrigin = GlobalTerminalState.restingBubbleOrigin(
                for: state.bubblePosition,
                in: proxy.size,
                buttonSize: buttonSize,
                padding: padding
            )

            let minX = padding
            let maxX = max(minX, proxy.size.width - buttonSize - padding)
            let minY: CGFloat = 28
            let maxY = max(minY, proxy.size.height - buttonSize - padding)

            let currentX = min(max(restingOrigin.x + dragOffset.width, minX), maxX)
            let currentY = min(max(restingOrigin.y + dragOffset.height, minY), maxY)

            ZStack(alignment: .topLeading) {
                bubbleContent
                    .frame(width: buttonSize, height: buttonSize)
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let dist = hypot(value.translation.width, value.translation.height)
                                if dist > 3 {
                                    isDragging = true
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                let dist = hypot(value.translation.width, value.translation.height)
                                if dist < 4 {
                                    onToggle()
                                    dragOffset = .zero
                                    isDragging = false
                                } else {
                                    let droppedPoint = CGPoint(
                                        x: min(max(restingOrigin.x + value.translation.width, minX), maxX),
                                        y: min(max(restingOrigin.y + value.translation.height, minY), maxY)
                                    )
                                    let newPos = GlobalTerminalState.snapBubbleToBorder(
                                        droppedPoint: droppedPoint,
                                        in: proxy.size,
                                        buttonSize: buttonSize,
                                        padding: padding
                                    )
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        state.saveBubblePosition(newPos)
                                        dragOffset = .zero
                                        isDragging = false
                                    }
                                }
                            }
                    )
                    .offset(x: currentX, y: currentY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var bubbleContent: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .frame(width: buttonSize, height: buttonSize)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isHovering || isDragging ? 0.25 : 0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isDragging ? 0.3 : 0.18), radius: isDragging ? 8 : 4, y: isDragging ? 4 : 2)

            Image(systemName: isActive ? "terminal.fill" : "terminal")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : (isHovering ? .primary : .secondary))
        }
        .frame(width: buttonSize, height: buttonSize)
        .contentShape(Circle())
        .scaleEffect(isDragging ? 1.08 : (isHovering ? 1.04 : 1.0))
        .animation(DesignMotion.interaction, value: isHovering)
        .animation(DesignMotion.interaction, value: isDragging)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelKey)
        .accessibilityHint("Toggles the persistent floating global terminal")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
        .help(accessibilityLabelKey)
    }
}

/// An AppKit NSView bridge that routes title-bar mouse drags to smooth real-time dragging constrained inside the Dockyard app boundaries.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context _: Context) -> DragView {
        DragView()
    }

    func updateNSView(_: DragView, context _: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let panel = window as? GlobalTerminalPanel,
                  let mainWindow = GlobalTerminalWindowController.shared.findMainWindow()
            else {
                window?.performDrag(with: event)
                return
            }

            panel.makeKeyAndOrderFront(nil)

            let initialMouse = NSEvent.mouseLocation
            let initialOrigin = panel.frame.origin
            let panelSize = panel.frame.size

            while true {
                guard let nextEvent = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
                if nextEvent.type == .leftMouseUp {
                    break
                }
                let currentMouse = NSEvent.mouseLocation
                let deltaX = currentMouse.x - initialMouse.x
                let deltaY = currentMouse.y - initialMouse.y
                let candidateOrigin = CGPoint(x: initialOrigin.x + deltaX, y: initialOrigin.y + deltaY)
                let clampedRect = GlobalTerminalState.clampPanelFrame(
                    NSRect(origin: candidateOrigin, size: panelSize),
                    inside: mainWindow.frame
                )
                panel.setFrameOrigin(clampedRect.origin)
            }

            GlobalTerminalWindowController.shared.notifyWindowDidMove()
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

    func findMainWindow() -> NSWindow? {
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible && $0.identifier?.rawValue == "main" }) {
            return window
        }
        if let mainWindow = NSApp.mainWindow, !(mainWindow is NSPanel) {
            return mainWindow
        }
        return NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey })
    }

    func notifyWindowDidMove() {
        guard let panel else { return }
        state?.savePosition(panel.frame.origin)
    }

    private var mainWindowObservers: [NSObjectProtocol] = []
    private var lastMainWindowFrame: NSRect?

    func observeMainWindow(_ mainWindow: NSWindow) {
        clearMainWindowObservers()
        lastMainWindowFrame = mainWindow.frame

        let center = NotificationCenter.default
        mainWindowObservers.append(
            center.addObserver(forName: NSWindow.didMoveNotification, object: mainWindow, queue: .main) { [weak self] _ in
                self?.mainWindowDidMove(mainWindow)
            }
        )
        mainWindowObservers.append(
            center.addObserver(forName: NSWindow.didResizeNotification, object: mainWindow, queue: .main) { [weak self] _ in
                self?.mainWindowDidResize(mainWindow)
            }
        )
        mainWindowObservers.append(
            center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: mainWindow, queue: .main) { [weak self] _ in
                self?.panel?.orderOut(nil)
            }
        )
        mainWindowObservers.append(
            center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: mainWindow, queue: .main) { [weak self] _ in
                guard let self, let state = self.state, state.isOpen, !state.isMinimized else { return }
                self.panel?.orderFrontRegardless()
            }
        )
    }

    private func clearMainWindowObservers() {
        for observer in mainWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        mainWindowObservers.removeAll()
    }

    private func mainWindowDidMove(_ mainWindow: NSWindow) {
        guard let panel else { return }
        let currentFrame = mainWindow.frame
        if let lastFrame = lastMainWindowFrame {
            let dx = currentFrame.origin.x - lastFrame.origin.x
            let dy = currentFrame.origin.y - lastFrame.origin.y
            if dx != 0 || dy != 0 {
                var newFrame = panel.frame.offsetBy(dx: dx, dy: dy)
                newFrame = GlobalTerminalState.clampPanelFrame(newFrame, inside: currentFrame)
                panel.setFrame(newFrame, display: true)
                state?.savePosition(newFrame.origin)
            }
        }
        lastMainWindowFrame = currentFrame
    }

    private func mainWindowDidResize(_ mainWindow: NSWindow) {
        guard let panel else { return }
        let currentFrame = mainWindow.frame
        let clamped = GlobalTerminalState.clampPanelFrame(panel.frame, inside: currentFrame)
        if clamped != panel.frame {
            panel.setFrame(clamped, display: true)
            state?.saveSize(clamped.size)
            state?.savePosition(clamped.origin)
        }
        lastMainWindowFrame = currentFrame
    }

    private func showPanel(state: GlobalTerminalState, surfaceCache: TerminalSurfaceCache) {
        if panel == nil {
            createPanel(state: state, surfaceCache: surfaceCache)
        }

        guard let panel else { return }
        if let mainWindow = findMainWindow() {
            observeMainWindow(mainWindow)
            let clamped = GlobalTerminalState.clampPanelFrame(panel.frame, inside: mainWindow.frame)
            if clamped != panel.frame {
                panel.setFrame(clamped, display: true)
            }
        }
        if let activeTabID = state.activeTabID {
            surfaceCache.setSurfaceAlwaysVisible(activeTabID, isAlwaysVisible: true)
        }
        panel.orderFrontRegardless()
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

        if let mainWindow = findMainWindow() {
            let mainFrame = mainWindow.frame
            let clampedSize = CGSize(
                width: min(initialSize.width, max(GlobalTerminalState.minWidth, mainFrame.width - GlobalTerminalState.padding * 2)),
                height: min(initialSize.height, max(GlobalTerminalState.minHeight, mainFrame.height - GlobalTerminalState.padding * 2))
            )
            let x = max(mainFrame.minX + GlobalTerminalState.padding, mainFrame.maxX - clampedSize.width - GlobalTerminalState.padding - 12)
            let y = max(mainFrame.minY + GlobalTerminalState.padding, mainFrame.minY + 48)
            let candidateRect = NSRect(origin: state.position ?? CGPoint(x: x, y: y), size: clampedSize)
            targetRect = GlobalTerminalState.clampPanelFrame(candidateRect, inside: mainFrame)
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenRect = screen.visibleFrame
            let x = screenRect.maxX - initialSize.width - 24
            let y = screenRect.minY + 48
            targetRect.origin = CGPoint(x: x, y: y)
        } else {
            targetRect.origin = CGPoint(x: 100, y: 100)
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
        panel.hidesOnDeactivate = false
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

    func windowWillResize(_: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let mainWindow = findMainWindow() else { return frameSize }
        let maxW = max(GlobalTerminalState.minWidth, mainWindow.frame.width - GlobalTerminalState.padding * 2)
        let maxH = max(GlobalTerminalState.minHeight, mainWindow.frame.height - GlobalTerminalState.padding * 2)
        return NSSize(width: min(frameSize.width, maxW), height: min(frameSize.height, maxH))
    }

    func windowDidMove(_: Notification) {
        guard let panel else { return }
        if let mainWindow = findMainWindow() {
            let clamped = GlobalTerminalState.clampPanelFrame(panel.frame, inside: mainWindow.frame)
            if clamped != panel.frame {
                panel.setFrame(clamped, display: true)
            }
        }
        state?.savePosition(panel.frame.origin)
    }

    func windowDidResize(_: Notification) {
        guard let panel else { return }
        if let mainWindow = findMainWindow() {
            let clamped = GlobalTerminalState.clampPanelFrame(panel.frame, inside: mainWindow.frame)
            if clamped != panel.frame {
                panel.setFrame(clamped, display: true)
            }
        }
        state?.saveSize(panel.frame.size)
        state?.savePosition(panel.frame.origin)
    }

    func windowWillClose(_: Notification) {
        guard let state, let surfaceCache else { return }
        state.close(surfaceCache: surfaceCache)
    }
}
