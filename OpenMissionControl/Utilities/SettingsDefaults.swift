//
//  SettingsDefaults.swift
//  OpenMissionControl
//
//  Created by Travis XU on 16/3/2026.
//

import Foundation

enum SettingsDefaults {
    // MARK: - Keys

    enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showQuitButton = "showQuitButton"
        static let showCloseButton = "showCloseButton"
        static let showMinimizeButton = "showMinimizeButton"
        static let showZoomButton = "showZoomButton"

        static let overlayTheme = "overlayTheme"
        static let overlayButtonScale = "overlayButtonScale"

        static let updateDuration = "updateDuration"
        static let mouseUpdateDuration = "mouseUpdateDuration"

        static let shortcutQuit = "shortcutQuit"
        static let shortcutClose = "shortcutClose"
        static let shortcutMinimize = "shortcutMinimize"
        static let shortcutMaximize = "shortcutMaximize"
        static let shortcutActivateWindow = "shortcutActivateWindow"

        static let rightClickAction = "rightClickAction"
        static let middleClickAction = "middleClickAction"
    }

    // MARK: - Defaults

    static let showMenuBarIcon: Bool = true
    static let showQuitButton: Bool = false
    static let showCloseButton: Bool = true
    static let showMinimizeButton: Bool = true
    static let showZoomButton: Bool = true

    static var overlayTheme: OverlayTheme {
        if #available(macOS 26.0, *) {
            return .liquidGlass
        }

        return .classic
    }
    static let overlayButtonScale: Double = 1.0

    static let updateDuration: Double = 0.1
    static let mouseUpdateDuration: Double = 0.1

    static let shortcutQuit: Bool = false
    static let shortcutClose: Bool = false
    static let shortcutMinimize: Bool = false
    static let shortcutMaximize: Bool = false
    static let shortcutActivateWindow: Bool = true

    static let rightClickAction: WindowAction = .none
    static let middleClickAction: WindowAction = .none
}
