// ABOUTME: Manages the lifecycle, position, and persistence of the persistent floating global terminal.
// ABOUTME: Operates independently of the selected project, workstream, or workspace.

import AppKit
import Foundation

/// Interactive edge or corner handle used to resize the floating terminal panel.
public enum ResizeHandle: CaseIterable, Sendable {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// Geometry definition describing the position and dimensions of the floating panel.
public struct PanelGeometry: Equatable, Sendable {
    public var position: CGPoint
    public var size: CGSize

    public init(position: CGPoint, size: CGSize) {
        self.position = position
        self.size = size
    }
}

/// Coordinates state, position persistence, and Ghostty surface lifecycles for Dockyard's floating global terminal.
@MainActor
final class GlobalTerminalState: ObservableObject {
    /// Dedicated dummy workstream ID used to isolate the global terminal from all workstreams.
    nonisolated static let globalWorkstreamID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Default width for the floating terminal panel.
    nonisolated static let defaultWidth: CGFloat = 640
    /// Default height for the floating terminal panel.
    nonisolated static let defaultHeight: CGFloat = 400
    /// Minimum allowed width when scaled down for smaller windows.
    nonisolated static let minWidth: CGFloat = 360
    /// Minimum allowed height when scaled down for smaller windows.
    nonisolated static let minHeight: CGFloat = 240
    /// Standard padding inset from window boundaries.
    nonisolated static let padding: CGFloat = 12

    /// The default initial working directory for the global terminal shell ($HOME).
    nonisolated static var defaultWorkingDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// The active working directory used by this global terminal instance.
    let workingDirectory: String

    /// Whether a global terminal session is currently open.
    @Published var isOpen: Bool
    /// Whether the global terminal panel is currently minimized to the floating button.
    @Published var isMinimized: Bool
    /// The current top-left position of the panel within the window coordinate space.
    @Published var position: CGPoint?
    /// The user-defined size of the floating terminal panel, if resized.
    @Published var size: CGSize?
    /// All active terminal tab surface IDs in display order.
    @Published var tabs: [UUID]
    /// The currently selected terminal tab surface ID.
    @Published var activeTabID: UUID?

    /// The unique surface ID corresponding to the active terminal session.
    var surfaceID: UUID? {
        activeTabID
    }

    private let userDefaults: UserDefaults

    /// Initializes state with optional custom UserDefaults and initial directory.
    ///
    /// - Parameters:
    ///   - userDefaults: The UserDefaults instance for persistence (defaults to .standard).
    ///   - workingDirectory: The initial directory for the terminal session (defaults to $HOME).
    init(
        userDefaults: UserDefaults = .standard,
        workingDirectory: String = GlobalTerminalState.defaultWorkingDirectory
    ) {
        self.userDefaults = userDefaults
        self.workingDirectory = workingDirectory

        let savedMinimized = userDefaults.bool(forKey: "dockyard.globalTerminal.isMinimized")
        let savedOpen = userDefaults.bool(forKey: "dockyard.globalTerminal.isOpen")

        isMinimized = savedMinimized
        isOpen = savedOpen

        if userDefaults.object(forKey: "dockyard.globalTerminal.positionX") != nil,
           userDefaults.object(forKey: "dockyard.globalTerminal.positionY") != nil
        {
            let x = CGFloat(userDefaults.double(forKey: "dockyard.globalTerminal.positionX"))
            let y = CGFloat(userDefaults.double(forKey: "dockyard.globalTerminal.positionY"))
            position = CGPoint(x: x, y: y)
        } else {
            position = nil
        }

        if userDefaults.object(forKey: "dockyard.globalTerminal.width") != nil,
           userDefaults.object(forKey: "dockyard.globalTerminal.height") != nil
        {
            let width = CGFloat(userDefaults.double(forKey: "dockyard.globalTerminal.width"))
            let height = CGFloat(userDefaults.double(forKey: "dockyard.globalTerminal.height"))
            size = CGSize(width: width, height: height)
        } else {
            size = nil
        }

        if savedOpen {
            let initialID = UUID()
            tabs = [initialID]
            activeTabID = initialID
        } else {
            tabs = []
            activeTabID = nil
        }
    }

    // MARK: - Lifecycle

    /// Opens a global terminal session, creating a new tab if one does not exist.
    ///
    /// - Parameter surfaceCache: Optional cache instance to mark the surface as visible.
    func open(surfaceCache: TerminalSurfaceCache? = nil) {
        if tabs.isEmpty {
            let newID = UUID()
            tabs.append(newID)
            activeTabID = newID
        } else if activeTabID == nil {
            activeTabID = tabs.first
        }
        isOpen = true
        isMinimized = false
        userDefaults.set(true, forKey: "dockyard.globalTerminal.isOpen")
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
        if let activeTabID {
            surfaceCache?.setSurfaceAlwaysVisible(activeTabID, isAlwaysVisible: true)
        }
    }

    /// Minimizes the global terminal panel, hiding the view while preserving running shell processes.
    ///
    /// - Parameter surfaceCache: Optional cache instance to mark the surface as occluded.
    func minimize(surfaceCache: TerminalSurfaceCache? = nil) {
        guard isOpen else { return }
        isMinimized = true
        userDefaults.set(true, forKey: "dockyard.globalTerminal.isMinimized")
        if let activeTabID {
            surfaceCache?.setSurfaceAlwaysVisible(activeTabID, isAlwaysVisible: false)
        }
    }

    /// Restores a minimized global terminal panel, revealing the existing running process.
    ///
    /// - Parameter surfaceCache: Optional cache instance to mark the surface as visible.
    func restore(surfaceCache: TerminalSurfaceCache? = nil) {
        if tabs.isEmpty {
            let newID = UUID()
            tabs.append(newID)
            activeTabID = newID
        } else if activeTabID == nil {
            activeTabID = tabs.first
        }
        isOpen = true
        isMinimized = false
        userDefaults.set(true, forKey: "dockyard.globalTerminal.isOpen")
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
        if let activeTabID {
            surfaceCache?.setSurfaceAlwaysVisible(activeTabID, isAlwaysVisible: true)
        }
    }

    /// Toggles the global terminal state between open, minimized, and restored.
    ///
    /// - Parameter surfaceCache: Optional cache instance to update surface visibility.
    func toggle(surfaceCache: TerminalSurfaceCache? = nil) {
        if !isOpen {
            open(surfaceCache: surfaceCache)
        } else if isMinimized {
            restore(surfaceCache: surfaceCache)
        } else {
            minimize(surfaceCache: surfaceCache)
        }
    }

    // MARK: - Tab Management

    /// Adds and activates a new terminal tab.
    ///
    /// - Parameter surfaceCache: Optional cache instance to mark the new surface as visible.
    /// - Returns: The newly created surface ID.
    @discardableResult
    func addNewTab(surfaceCache: TerminalSurfaceCache? = nil) -> UUID {
        if let currentActive = activeTabID {
            surfaceCache?.setSurfaceAlwaysVisible(currentActive, isAlwaysVisible: false)
        }
        let newID = UUID()
        tabs.append(newID)
        activeTabID = newID
        if !isOpen {
            isOpen = true
            isMinimized = false
            userDefaults.set(true, forKey: "dockyard.globalTerminal.isOpen")
            userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
        }
        surfaceCache?.setSurfaceAlwaysVisible(newID, isAlwaysVisible: true)
        return newID
    }

    /// Closes a specific terminal tab by ID.
    ///
    /// - Parameters:
    ///   - id: The surface ID of the tab to close.
    ///   - surfaceCache: Optional cache instance to evict the surface.
    func closeTab(_ id: UUID, surfaceCache: TerminalSurfaceCache? = nil) {
        surfaceCache?.setSurfaceAlwaysVisible(id, isAlwaysVisible: false)
        surfaceCache?.removeSurface(for: id)
        guard let idx = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: idx)

        if tabs.isEmpty {
            close(surfaceCache: surfaceCache)
        } else if activeTabID == id {
            let newIdx = min(idx, tabs.count - 1)
            activeTabID = tabs[newIdx]
            if let activeTabID {
                surfaceCache?.setSurfaceAlwaysVisible(activeTabID, isAlwaysVisible: true)
            }
        }
    }

    /// Closes the currently active terminal tab.
    ///
    /// - Parameter surfaceCache: Optional cache instance to evict the surface.
    func closeActiveTab(surfaceCache: TerminalSurfaceCache? = nil) {
        if let activeTabID {
            closeTab(activeTabID, surfaceCache: surfaceCache)
        } else {
            close(surfaceCache: surfaceCache)
        }
    }

    /// Selects a specific terminal tab.
    ///
    /// - Parameters:
    ///   - id: The surface ID of the tab to activate.
    ///   - surfaceCache: Optional cache instance to update occlusion.
    func selectTab(_ id: UUID, surfaceCache: TerminalSurfaceCache? = nil) {
        guard tabs.contains(id), id != activeTabID else { return }
        if let current = activeTabID {
            surfaceCache?.setSurfaceAlwaysVisible(current, isAlwaysVisible: false)
        }
        activeTabID = id
        surfaceCache?.setSurfaceAlwaysVisible(id, isAlwaysVisible: true)
    }

    /// Cycles forward to the next terminal tab.
    ///
    /// - Parameter surfaceCache: Optional cache instance to update occlusion.
    func selectNextTab(surfaceCache: TerminalSurfaceCache? = nil) {
        guard !tabs.isEmpty, let activeTabID, let idx = tabs.firstIndex(of: activeTabID) else { return }
        let nextIdx = (idx + 1) % tabs.count
        selectTab(tabs[nextIdx], surfaceCache: surfaceCache)
    }

    /// Cycles backward to the previous terminal tab.
    ///
    /// - Parameter surfaceCache: Optional cache instance to update occlusion.
    func selectPreviousTab(surfaceCache: TerminalSurfaceCache? = nil) {
        guard !tabs.isEmpty, let activeTabID, let idx = tabs.firstIndex(of: activeTabID) else { return }
        let prevIdx = (idx - 1 + tabs.count) % tabs.count
        selectTab(tabs[prevIdx], surfaceCache: surfaceCache)
    }

    /// Selects the terminal tab at a 0-based index (e.g. for Cmd+1..9).
    ///
    /// - Parameters:
    ///   - index: The 0-based tab index.
    ///   - surfaceCache: Optional cache instance to update occlusion.
    func selectTabAtIndex(_ index: Int, surfaceCache: TerminalSurfaceCache? = nil) {
        guard index >= 0, index < tabs.count else { return }
        selectTab(tabs[index], surfaceCache: surfaceCache)
    }

    /// Closes and destroys all active global terminal sessions, evicting them from the surface cache.
    ///
    /// - Parameter surfaceCache: Optional cache instance from which to remove the surfaces.
    func close(surfaceCache: TerminalSurfaceCache? = nil) {
        for id in tabs {
            surfaceCache?.setSurfaceAlwaysVisible(id, isAlwaysVisible: false)
            surfaceCache?.removeSurface(for: id)
        }
        tabs.removeAll()
        activeTabID = nil
        isOpen = false
        isMinimized = false
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isOpen")
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
    }

    /// Handles cleanup when a terminal shell process terminates (e.g. exit command).
    ///
    /// - Parameters:
    ///   - surfaceID: The surface ID of the terminated process, or nil for the active tab.
    ///   - surfaceCache: Optional cache instance to update occlusion tracking and evict the dead surface.
    func handleProcessTerminated(surfaceID: UUID? = nil, surfaceCache: TerminalSurfaceCache? = nil) {
        let targetID = surfaceID ?? activeTabID
        if let targetID, tabs.contains(targetID) {
            closeTab(targetID, surfaceCache: surfaceCache)
        } else {
            close(surfaceCache: surfaceCache)
        }
    }

    /// Persists a new panel position to UserDefaults.
    ///
    /// - Parameter newPosition: The new top-left coordinates of the floating panel.
    func savePosition(_ newPosition: CGPoint) {
        position = newPosition
        userDefaults.set(Double(newPosition.x), forKey: "dockyard.globalTerminal.positionX")
        userDefaults.set(Double(newPosition.y), forKey: "dockyard.globalTerminal.positionY")
    }

    /// Persists a new panel size to UserDefaults.
    ///
    /// - Parameter newSize: The new dimensions of the floating panel.
    func saveSize(_ newSize: CGSize) {
        size = newSize
        userDefaults.set(Double(newSize.width), forKey: "dockyard.globalTerminal.width")
        userDefaults.set(Double(newSize.height), forKey: "dockyard.globalTerminal.height")
    }

    // MARK: - Geometry & Clamping

    /// Computes the effective panel size adapted to the current window size and optional user size.
    ///
    /// - Parameters:
    ///   - windowSize: The current dimensions of the host window.
    ///   - customSize: The user's preferred custom panel size, if set.
    ///   - defaultSize: The preferred default panel size.
    ///   - minSize: The minimum allowed panel size.
    ///   - padding: Padding around the window edges.
    /// - Returns: Clamped CGSize for the panel.
    nonisolated static func effectivePanelSize(
        windowSize: CGSize,
        customSize: CGSize? = nil,
        defaultSize: CGSize = CGSize(width: defaultWidth, height: defaultHeight),
        minSize: CGSize = CGSize(width: minWidth, height: minHeight),
        padding: CGFloat = padding
    ) -> CGSize {
        let base = customSize ?? defaultSize
        let availableWidth = max(minSize.width, windowSize.width - padding * 2)
        let availableHeight = max(minSize.height, windowSize.height - padding * 2)
        return CGSize(
            width: min(max(base.width, minSize.width), availableWidth),
            height: min(max(base.height, minSize.height), availableHeight)
        )
    }

    /// Calculates the updated position and size resulting from an edge or corner resize gesture.
    ///
    /// - Parameters:
    ///   - handle: The edge or corner handle being dragged.
    ///   - translation: The mouse translation delta during the resize gesture.
    ///   - basePosition: The panel's top-left origin before resizing began.
    ///   - baseSize: The panel's dimensions before resizing began.
    ///   - windowSize: The dimensions of the host window.
    ///   - minWidth: The minimum allowed panel width.
    ///   - minHeight: The minimum allowed panel height.
    ///   - padding: Inset boundary from host window edges.
    /// - Returns: The resulting clamped panel position and size.
    nonisolated static func calculateResizedGeometry(
        handle: ResizeHandle,
        translation: CGSize,
        basePosition: CGPoint,
        baseSize: CGSize,
        windowSize: CGSize,
        minWidth: CGFloat = minWidth,
        minHeight: CGFloat = minHeight,
        padding: CGFloat = padding
    ) -> PanelGeometry {
        var x = basePosition.x
        var y = basePosition.y
        var w = baseSize.width
        var h = baseSize.height

        // Horizontal resize
        switch handle {
        case .right, .topRight, .bottomRight:
            let maxWFromX = max(minWidth, windowSize.width - padding - x)
            let candidateW = baseSize.width + translation.width
            w = min(max(candidateW, minWidth), maxWFromX)

        case .left, .topLeft, .bottomLeft:
            let rightEdge = basePosition.x + baseSize.width
            let minX = padding
            let maxX = rightEdge - minWidth
            let candidateX = basePosition.x + translation.width
            x = min(max(candidateX, minX), maxX)
            w = rightEdge - x

        case .top, .bottom:
            break
        }

        // Vertical resize
        switch handle {
        case .bottom, .bottomLeft, .bottomRight:
            let maxHFromY = max(minHeight, windowSize.height - padding - y)
            let candidateH = baseSize.height + translation.height
            h = min(max(candidateH, minHeight), maxHFromY)

        case .top, .topLeft, .topRight:
            let bottomEdge = basePosition.y + baseSize.height
            let minY = padding
            let maxY = bottomEdge - minHeight
            let candidateY = basePosition.y + translation.height
            y = min(max(candidateY, minY), maxY)
            h = bottomEdge - y

        case .left, .right:
            break
        }

        return PanelGeometry(
            position: CGPoint(x: x, y: y),
            size: CGSize(width: w, height: h)
        )
    }

    /// Calculates the initial default position for the panel near the bottom-right corner.
    ///
    /// - Parameters:
    ///   - panelSize: The size of the floating panel.
    ///   - windowSize: The size of the host window.
    ///   - padding: Additional padding from the edge.
    /// - Returns: Clamped CGPoint for top-left panel position.
    nonisolated static func defaultPosition(
        panelSize: CGSize,
        windowSize: CGSize,
        padding: CGFloat = 16
    ) -> CGPoint {
        let x = max(Self.padding, windowSize.width - panelSize.width - padding)
        let y = max(Self.padding, windowSize.height - panelSize.height - padding - 48)
        return clampedPosition(CGPoint(x: x, y: y), panelSize: panelSize, windowSize: windowSize)
    }

    /// Clamps a candidate position to ensure the entire panel remains within the visible window.
    ///
    /// - Parameters:
    ///   - position: Candidate top-left coordinate.
    ///   - panelSize: Dimensions of the floating panel.
    ///   - windowSize: Dimensions of the host window.
    ///   - padding: Inset from the window edge.
    /// - Returns: Clamped CGPoint guaranteed to lie within visible bounds.
    nonisolated static func clampedPosition(
        _ position: CGPoint,
        panelSize: CGSize,
        windowSize: CGSize,
        padding: CGFloat = padding
    ) -> CGPoint {
        let minX = padding
        let maxX = max(padding, windowSize.width - panelSize.width - padding)
        let minY = padding
        let maxY = max(padding, windowSize.height - panelSize.height - padding)

        let clampedX = min(max(position.x, minX), maxX)
        let clampedY = min(max(position.y, minY), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }
}
