// ABOUTME: Manages the lifecycle, position, and persistence of the persistent floating global terminal.
// ABOUTME: Operates independently of the selected project, workstream, or workspace.

import AppKit
import Foundation

@MainActor
final class GlobalTerminalState: ObservableObject {
    nonisolated static let globalWorkstreamID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    nonisolated static let defaultWidth: CGFloat = 640
    nonisolated static let defaultHeight: CGFloat = 400
    nonisolated static let minWidth: CGFloat = 360
    nonisolated static let minHeight: CGFloat = 240
    nonisolated static let padding: CGFloat = 12

    nonisolated static var defaultWorkingDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    let workingDirectory: String

    @Published var isOpen: Bool
    @Published var isMinimized: Bool
    @Published var position: CGPoint?
    @Published private(set) var surfaceID: UUID?

    private let userDefaults: UserDefaults

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

    func minimize(surfaceCache: TerminalSurfaceCache? = nil) {
        guard isOpen else { return }
        isMinimized = true
        userDefaults.set(true, forKey: "dockyard.globalTerminal.isMinimized")
        if let surfaceID {
            surfaceCache?.setSurfaceAlwaysVisible(surfaceID, isAlwaysVisible: false)
        }
    }

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

    func toggle(surfaceCache: TerminalSurfaceCache? = nil) {
        if !isOpen {
            open(surfaceCache: surfaceCache)
        } else if isMinimized {
            restore(surfaceCache: surfaceCache)
        } else {
            minimize(surfaceCache: surfaceCache)
        }
    }

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

    func handleProcessTerminated(surfaceCache: TerminalSurfaceCache? = nil) {
        if let surfaceID {
            surfaceCache?.setSurfaceAlwaysVisible(surfaceID, isAlwaysVisible: false)
        }
        surfaceID = nil
        isOpen = false
        isMinimized = false
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isOpen")
        userDefaults.set(false, forKey: "dockyard.globalTerminal.isMinimized")
    }

    func savePosition(_ newPosition: CGPoint) {
        position = newPosition
        userDefaults.set(Double(newPosition.x), forKey: "dockyard.globalTerminal.positionX")
        userDefaults.set(Double(newPosition.y), forKey: "dockyard.globalTerminal.positionY")
    }

    // MARK: - Geometry & Clamping

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

    nonisolated static func defaultPosition(
        panelSize: CGSize,
        windowSize: CGSize,
        padding: CGFloat = 16
    ) -> CGPoint {
        let x = max(Self.padding, windowSize.width - panelSize.width - padding)
        let y = max(Self.padding, windowSize.height - panelSize.height - padding - 48)
        return clampedPosition(CGPoint(x: x, y: y), panelSize: panelSize, windowSize: windowSize)
    }

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
