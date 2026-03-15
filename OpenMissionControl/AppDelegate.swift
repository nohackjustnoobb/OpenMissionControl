//
//  AppDelegate.swift
//  OpenMissionControl
//
//  Created by Travis XU on 16/3/2026.
//

import Foundation
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        OpenMissionControlCore.shared.start()
        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        OpenMissionControlCore.shared.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Open Mission Control")
        }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        SettingsViewManager.shared.showSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
