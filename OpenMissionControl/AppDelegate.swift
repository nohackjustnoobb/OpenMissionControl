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
    private var userDefaultsObserver: NSObjectProtocol?
    private let openSettingsOnLaunch: Bool

    init(openSettingsOnLaunch: Bool = false) {
        self.openSettingsOnLaunch = openSettingsOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        OpenMissionControlCore.shared.start()
        observeUserDefaults()
        setupStatusItem()

        if openSettingsOnLaunch {
            SettingsViewManager.shared.showSettings()
        }
    }

    func applicationWillTerminate(_: Notification) {
        if let userDefaultsObserver {
            NotificationCenter.default.removeObserver(userDefaultsObserver)
        }
        OpenMissionControlCore.shared.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItemVisibility()

        let appName =
            Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Open Mission Control"
        let appVersion =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.3.group.fill", accessibilityDescription: appName)
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(
            title: "\(appName) v\(appVersion) (\(appBuild))", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func observeUserDefaults() {
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItemVisibility()
            }
        }
    }

    private func updateStatusItemVisibility() {
        let showMenuBarIcon = UserDefaults.standard.object(
            forKey: SettingsDefaults.Key.showMenuBarIcon
        ) as? Bool ?? SettingsDefaults.showMenuBarIcon
        statusItem?.isVisible = showMenuBarIcon
    }

    @objc private func openSettings() {
        SettingsViewManager.shared.showSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
