//
//  SettingsViewManager.swift
//  OpenMissionControl
//
//  Created by Travis XU on 16/3/2026.
//

import AppKit
import Combine
import SwiftUI

class SettingsViewManager: NSObject, ObservableObject {
    static let shared = SettingsViewManager()

    private var settingsWindowController: NSWindowController?

    func showSettings() {
        if settingsWindowController == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            let fittingSize = hostingController.view.fittingSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: fittingSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            window.contentViewController = hostingController
            window.isReleasedWhenClosed = true
            window.delegate = self
            window.titlebarAppearsTransparent = true
            window.title = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Open Mission Control"
            window.toolbar = NSToolbar()

            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension SettingsViewManager: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        settingsWindowController = nil
    }
}
