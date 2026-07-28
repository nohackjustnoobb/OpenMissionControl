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
        static let showQuitButton = "showQuitButton"
        static let showCloseButton = "showCloseButton"
        static let showMinimizeButton = "showMinimizeButton"
        static let showZoomButton = "showZoomButton"

        static let overlayTheme = "overlayTheme"

        static let updateDuration = "updateDuration"
        static let mouseUpdateDuration = "mouseUpdateDuration"

        static let shortcutQuit = "shortcutQuit"
        static let shortcutClose = "shortcutClose"
        static let shortcutMinimize = "shortcutMinimize"
        static let shortcutMaximize = "shortcutMaximize"

        static let keyboardNavigation = "keyboardNavigation"
        static let tabNavigationExtraKey = "tabNavigationExtraKey"
        static let enterNavigationExtraKey = "enterNavigationExtraKey"

        static let rightClickAction = "rightClickAction"
        static let middleClickAction = "middleClickAction"
    }

    // MARK: - Defaults

    static let showQuitButton: Bool = false
    static let showCloseButton: Bool = true
    static let showMinimizeButton: Bool = true
    static let showZoomButton: Bool = true

    static let overlayTheme: OverlayTheme = .default

    static let updateDuration: Double = 0.25
    static let mouseUpdateDuration: Double = 0.1

    static let shortcutQuit: Bool = false
    static let shortcutClose: Bool = false
    static let shortcutMinimize: Bool = false
    static let shortcutMaximize: Bool = false

    static let keyboardNavigation: Bool = true
    static let tabNavigationExtraKey: NavigationKey = .d
    static let enterNavigationExtraKey: NavigationKey = .k

    static let rightClickAction: WindowAction = .none
    static let middleClickAction: WindowAction = .none
}
