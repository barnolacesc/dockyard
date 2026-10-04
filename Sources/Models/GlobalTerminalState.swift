// ABOUTME: Manages the lifecycle, position, and persistence of the persistent floating global terminal.
// ABOUTME: Operates independently of the selected project, workstream, or workspace.

import AppKit
import Foundation

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
    /// The unique surface ID corresponding to the active terminal session.
    @Published private(set) var surfaceID: UUID?

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

        if savedOpen {
            surfaceID = UUID()
        } else {
            surfaceID = nil
        }
    }

    // MARK: - Lifecycle

    /// Opens a global terminal session, creating a new surface ID if one does not exist.
    ///
    /// - Parameter surfaceCache: Optional cache instance to mark the surface as visible.
    func open(surfaceCache: TerminalSurfaceCache? = nil) {
        if surfaceID == nil {
            surfaceID = UUID()
        }
        isOpen = true
        isMinimized = false
        userDefaults.set(true, forKey: "dockyard.globalTerminal.isOpen")
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
        if let surfaceID {
            surfaceCache?.setSurfaceAlwaysVisible(surfaceID, isAlwaysVisible: true)
        }
    }

    /// Minimizes the global terminal panel, hiding the view while preserving the running shell process.
    ///
    /// - Parameter surfaceCache: Optional cache instance to mark the surface as occluded.
    func minimize(surfaceCache: TerminalSurfaceCache? = nil) {
        guard isOpen else { return }
        isMinimized = true
        userDefaults.set(true, forKey: "dockyard.globalTerminal.isMinimized")
        if let surfaceID {
            surfaceCache?.setSurfaceAlwaysVisible(surfaceID, isAlwaysVisible: false)
        }
    }

    /// Restores a minimized global terminal panel, revealing the existing running process.
    ///
    /// - Parameter surfaceCache: Optional cache instance to mark the surface as visible.
    func restore(surfaceCache: TerminalSurfaceCache? = nil) {
        if surfaceID == nil {
            surfaceID = UUID()
        }
        isOpen = true
        isMinimized = false
        userDefaults.set(true, forKey: "dockyard.globalTerminal.isOpen")
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
        if let surfaceID {
            surfaceCache?.setSurfaceAlwaysVisible(surfaceID, isAlwaysVisible: true)
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

    /// Closes and destroys the active global terminal session, evicting it from the surface cache.
    ///
    /// - Parameter surfaceCache: Optional cache instance from which to remove the surface.
    func close(surfaceCache: TerminalSurfaceCache? = nil) {
        if let surfaceID {
            surfaceCache?.setSurfaceAlwaysVisible(surfaceID, isAlwaysVisible: false)
            surfaceCache?.removeSurface(for: surfaceID)
        }
        surfaceID = nil
        isOpen = false
        isMinimized = false
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isOpen")
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
    }

    /// Handles cleanup when the terminal shell process terminates (e.g. exit command).
    ///
    /// - Parameter surfaceCache: Optional cache instance to update occlusion tracking and evict the dead surface.
    func handleProcessTerminated(surfaceCache: TerminalSurfaceCache? = nil) {
        if let surfaceID {
            surfaceCache?.setSurfaceAlwaysVisible(surfaceID, isAlwaysVisible: false)
            surfaceCache?.removeSurface(for: surfaceID)
        }
        surfaceID = nil
        isOpen = false
        isMinimized = false
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isOpen")
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
    }

    /// Persists a new panel position to UserDefaults.
    ///
    /// - Parameter newPosition: The new top-left coordinates of the floating panel.
    func savePosition(_ newPosition: CGPoint) {
        position = newPosition
        userDefaults.set(Double(newPosition.x), forKey: "dockyard.globalTerminal.positionX")
        userDefaults.set(Double(newPosition.y), forKey: "dockyard.globalTerminal.positionY")
    }

    // MARK: - Geometry & Clamping

    /// Computes the effective panel size adapted to the current window size.
    ///
    /// - Parameters:
    ///   - windowSize: The current dimensions of the host window.
    ///   - defaultSize: The preferred default panel size.
    ///   - minSize: The minimum allowed panel size.
    ///   - padding: Padding around the window edges.
    /// - Returns: Clamped CGSize for the panel.
    nonisolated static func effectivePanelSize(
        windowSize: CGSize,
        defaultSize: CGSize = CGSize(width: defaultWidth, height: defaultHeight),
        minSize: CGSize = CGSize(width: minWidth, height: minHeight),
        padding: CGFloat = padding
    ) -> CGSize {
        let availableWidth = max(minSize.width, windowSize.width - padding * 2)
        let availableHeight = max(minSize.height, windowSize.height - padding * 2)
        return CGSize(
            width: min(defaultSize.width, availableWidth),
            height: min(defaultSize.height, availableHeight)
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
