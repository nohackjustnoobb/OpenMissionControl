//
//  MissionControlMonitor.swift
//  OpenMissionControl
//
//  Created by Travis XU on 15/3/2026.
//

// Based on implementations from lwouis's alt-tab-macos (GNU GPL v3.0):
// - https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/ApplicationServices.HIServices.framework.swift
// - https://github.com/lwouis/alt-tab-macos/blob/master/src/events/DockEvents.swift
// - https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/MissionControl.swift

import AppKit
import ApplicationServices
import CoreGraphics
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

    private var axUiElement: AXUIElement?
    private var axObserver: AXObserver?
    private var overlayPollTimer: Timer?

    // macOS 27 stopped posting the Dock's AXExpose* notifications. Mission Control's
    // WindowManager overlays remain observable without Screen Recording permission.
    private let windowManagerProcessName = "WindowManager"
    private let exposeShieldLevel = 19
    private let showDesktopOverlayLevel = 18
    private let spacesBarLevel = 14
    private let overlayPollInterval: TimeInterval = 0.25

    // MARK: - Public Interface

    func setHandler(_ handler: @escaping StateHandler) {
        self.handler = handler
    }

    func start() {
        guard !isMonitoring else { return }

        let isMacOS27OrLater = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        let isAXMonitoring = startAXMonitoring()

        if isMacOS27OrLater {
            startOverlayMonitoring()
        }

        guard isAXMonitoring || overlayPollTimer != nil else {
            logger.error("Mission Control monitoring could not be started.")
            return
        }

        isMonitoring = true
        logger.info(
            "Mission Control monitoring started (AX: \(isAXMonitoring), overlays: \(self.overlayPollTimer != nil))."
        )
    }

    func stop() {
        guard isMonitoring else { return }

        if let observer = axObserver, let element = axUiElement {
            for notification in MissionControlState.allCases {
                AXObserverRemoveNotification(observer, element, notification.rawValue as CFString)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }

        axObserver = nil
        axUiElement = nil
        overlayPollTimer?.invalidate()
        overlayPollTimer = nil
        isMonitoring = false
        currentState = .inactive
        logger.info("Mission Control monitoring stopped.")
    }

    // MARK: - Private Helpers

    fileprivate func notifyHandlerIfNeeded(newState: MissionControlState) {
        guard currentState != newState else { return }

        currentState = newState
        handler?(newState)
    }

    private func startAXMonitoring() -> Bool {
        guard let dockPid = getDockPID() else {
            logger.error("Could not find the Dock process.")
            return false
        }

        let element = AXUIElementCreateApplication(dockPid)
        var observer: AXObserver?
        let createResult = AXObserverCreate(dockPid, axObserverCallback, &observer)
        guard createResult == .success, let observer else {
            logger.error("Could not create Dock AX observer: \(createResult.rawValue).")
            return false
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        for notification in MissionControlState.allCases {
            let result = AXObserverAddNotification(
                observer, element, notification.rawValue as CFString, selfPtr)
            if result != .success {
                logger.warning(
                    "Could not observe \(notification.rawValue): \(result.rawValue).")
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axUiElement = element
        axObserver = observer
        return true
    }

    private func startOverlayMonitoring() {
        updateStateFromWindowManagerOverlays()

        let timer = Timer(timeInterval: overlayPollInterval, repeats: true) { [weak self] _ in
            self?.updateStateFromWindowManagerOverlays()
        }
        RunLoop.main.add(timer, forMode: .common)
        overlayPollTimer = timer
    }

    private func updateStateFromWindowManagerOverlays() {
        let windowList =
            CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] ?? []

        var hasExposeShield = false
        var hasSpacesBar = false
        var hasShowDesktopOverlay = false

        for window in windowList {
            guard
                window[kCGWindowOwnerName as String] as? String == windowManagerProcessName,
                let layer = window[kCGWindowLayer as String] as? Int
            else { continue }

            switch layer {
            case exposeShieldLevel:
                hasExposeShield = true
            case showDesktopOverlayLevel:
                hasShowDesktopOverlay = true
            case spacesBarLevel:
                hasSpacesBar = true
            default:
                continue
            }
        }

        let state: MissionControlState
        if hasExposeShield {
            state = hasSpacesBar ? .showAllWindows : .showFrontWindows
        } else {
            state = hasShowDesktopOverlay ? .showDesktop : .inactive
        }

        notifyHandlerIfNeeded(newState: state)
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
