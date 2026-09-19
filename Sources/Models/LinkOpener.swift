// ABOUTME: Central routing for opening links (in-app browser, external browser, or prompting user).
// ABOUTME: Respects user preference in dockyard.linkOpenTarget.

import AppKit
import Foundation
import SwiftUI

public enum LinkOpenTarget: String, CaseIterable, Identifiable {
    case inApp
    case external
    case ask

    public var id: String { rawValue }

    public var displayName: LocalizedStringKey {
        switch self {
        case .inApp:
            return "In-App Browser"
        case .external:
            return "External Browser"
        case .ask:
            return "Ask Each Time"
        }
    }
}

@MainActor
public enum LinkOpener {
    public static let targetStorageKey = "dockyard.linkOpenTarget"

    public static var currentTarget: LinkOpenTarget {
        get {
            guard let raw = UserDefaults.standard.string(forKey: targetStorageKey),
                  let target = LinkOpenTarget(rawValue: raw) else {
                return .external
            }
            return target
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: targetStorageKey)
        }
    }

    public static func open(url: URL, workstreamID: UUID?) {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else {
            NSWorkspace.shared.open(url)
            return
        }

        switch currentTarget {
        case .inApp:
            openInApp(url: url, workstreamID: workstreamID)
        case .external:
            openExternal(url: url)
        case .ask:
            promptAndOpen(url: url, workstreamID: workstreamID)
        }
    }

    public static func openInApp(url: URL, workstreamID: UUID?) {
        let resolvedWSID = workstreamID ?? SidebarSelection.loadSaved()?.workstreamID
        if let resolvedWSID {
            NotificationCenter.default.post(
                name: .openInAppBrowser,
                object: resolvedWSID,
                userInfo: ["url": url]
            )
        } else {
            openExternal(url: url)
        }
    }

    public static func openExternal(url: URL) {
        let defaultBrowser = UserDefaults.standard.string(forKey: "dockyard.defaultBrowser") ?? ""
        if !defaultBrowser.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: defaultBrowser) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private static func promptAndOpen(url: URL, workstreamID: UUID?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Open Link", comment: "")
        alert.informativeText = url.absoluteString
        alert.addButton(withTitle: NSLocalizedString("In-App Browser", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("External Browser", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = NSLocalizedString("Always use this choice", comment: "")

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window) { response in
                handleAlertResponse(response, alert: alert, url: url, workstreamID: workstreamID)
            }
        } else {
            let response = alert.runModal()
            handleAlertResponse(response, alert: alert, url: url, workstreamID: workstreamID)
        }
    }

    private static func handleAlertResponse(
        _ response: NSApplication.ModalResponse,
        alert: NSAlert,
        url: URL,
        workstreamID: UUID?
    ) {
        let remember = alert.suppressionButton?.state == .on
        if response == .alertFirstButtonReturn {
            if remember {
                currentTarget = .inApp
            }
            openInApp(url: url, workstreamID: workstreamID)
        } else if response == .alertSecondButtonReturn {
            if remember {
                currentTarget = .external
            }
            openExternal(url: url)
        }
    }
}
