//
//  AppDelegate.swift
//  OpenMissionControl
//
//  Created by Travis XU on 16/3/2026.
//

import AppKit
import Foundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_: Notification) {
        OpenMissionControlCore.shared.start()
        setupStatusItem()
    }

    func applicationWillTerminate(_: Notification) {
        OpenMissionControlCore.shared.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Open Mission Control"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group.fill", accessibilityDescription: appName)
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "\(appName) v\(appVersion) (\(appBuild))", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())

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
