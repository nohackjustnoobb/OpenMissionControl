//
//  MissionControlMonitor.swift
//  OpenMissionControl
//
//  Created by Travis XU on 15/3/2026.
//

// Based on implementations from lwouis's alt-tab-macos (GNU GPL v3.0):
// - https://github.com/lwouis/alt-tab-macos/blob/master/src/api-wrappers/private-apis/ApplicationServices.HIServices.framework.swift
// - https://github.com/lwouis/alt-tab-macos/blob/master/src/logic/events/DockEvents.swift

import AppKit
import ApplicationServices
import Foundation
import os

enum MissionControlState: String, CaseIterable {
    case showAllWindows = "AXExposeShowAllWindows"
    case showFrontWindows = "AXExposeShowFrontWindows"
    case showDesktop = "AXExposeShowDesktop"
    case inactive = "AXExposeExit"

    var isActive: Bool {
        self != .inactive
    }
}

class MissionControlMonitor {
    static let shared = MissionControlMonitor()

    // MARK: - Types

    typealias StateHandler = (MissionControlState) -> Void

    // MARK: - Properties

    private let logger = Logger(
        subsystem: "dev.travisxu.OpenMissionControl",
        category: "MissionControlMonitor"
    )

    private var handler: StateHandler?
    private(set) var isMonitoring: Bool = false
    private(set) var currentState: MissionControlState = .inactive

    // MARK: - Public Interface

    func setHandler(_ handler: @escaping StateHandler) {
        self.handler = handler
    }

    private var axUiElement: AXUIElement?
    private var axObserver: AXObserver?

    func start() {
        guard !isMonitoring else { return }

        guard let dockPid = getDockPID() else { return }
        axUiElement = AXUIElementCreateApplication(dockPid)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AXObserverCreate(dockPid, axObserverCallback, &axObserver)

        guard let axObserver = axObserver, let axUiElement = axUiElement else { return }

        for notification in MissionControlState.allCases {
            AXObserverAddNotification(axObserver, axUiElement, notification.rawValue as CFString, selfPtr)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)

        isMonitoring = true
        logger.info("Mission Control monitoring started.")
    }

    func stop() {
        guard isMonitoring else { return }

        if let observer = axObserver, let element = axUiElement {
            for notification in MissionControlState.allCases {
                AXObserverRemoveNotification(observer, element, notification.rawValue as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }

        axObserver = nil
        axUiElement = nil
        isMonitoring = false
        logger.info("Mission Control monitoring stopped.")
    }

    // MARK: - Private Helpers

    fileprivate func notifyHandlerIfNeeded(newState: MissionControlState) {
        guard currentState != newState else { return }

        currentState = newState
        handler?(newState)
    }

    private func getDockPID() -> pid_t? {
        let dockBundleID = "com.apple.dock"
        let runningApps = NSWorkspace.shared.runningApplications

        // Find the application with the matching bundle ID
        if let dockApp = runningApps.first(where: { $0.bundleIdentifier == dockBundleID }) {
            return dockApp.processIdentifier
        }

        return nil
    }
}

// MARK: - AXObserver Callback

/// Top-level C-compatible callback required by AXObserverCreate.
/// Recovers the `MissionControlMonitor` instance from `refcon` and
/// forwards the notification to `notifyHandlerIfNeeded`.
private func axObserverCallback(
    _: AXObserver,
    _: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }

    let monitor = Unmanaged<MissionControlMonitor>.fromOpaque(refcon).takeUnretainedValue()

    if let state = MissionControlState(rawValue: notification as String) {
        monitor.notifyHandlerIfNeeded(newState: state)
    }
}
