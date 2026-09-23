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

private typealias CGSConnectionID = UInt32
private typealias CGSConnectionNotifyProc =
    @convention(c) (
        _ event: UInt32,
        _ data: UnsafeMutableRawPointer?,
        _ dataLength: Int,
        _ context: UnsafeMutableRawPointer?,
        _ connection: CGSConnectionID
    ) -> Void
private typealias SLSRegisterConnectionNotifyProcFunction =
    @convention(c) (
        _ connection: CGSConnectionID,
        _ callback: CGSConnectionNotifyProc,
        _ event: UInt32,
        _ context: UnsafeMutableRawPointer?
    ) -> CGError
private typealias SLSRequestNotificationsForWindowsFunction =
    @convention(c) (
        _ connection: CGSConnectionID,
        _ windowList: UnsafeMutablePointer<CGWindowID>,
        _ windowCount: Int32
    ) -> CGError

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

private let skyLightHandle = dlopen(
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
    RTLD_LAZY | RTLD_LOCAL
)

private func skyLightSymbol<T>(_ name: String, as _: T.Type) -> T? {
    guard let skyLightHandle, let symbol = dlsym(skyLightHandle, name) else { return nil }
    return unsafeBitCast(symbol, to: T.self)
}

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
    private var overlayUpdateWorkItem: DispatchWorkItem?
    private var areWindowServerNotificationsRegistered = false
    private var isOverlayEventMonitoring = false
    private var isOverlayStateAuthoritative = false
    private var subscribedWindowIDs = Set<CGWindowID>()
    private let registerConnectionNotifyProc = skyLightSymbol(
        "SLSRegisterConnectionNotifyProc",
        as: SLSRegisterConnectionNotifyProcFunction.self
    )
    private let requestNotificationsForWindows = skyLightSymbol(
        "SLSRequestNotificationsForWindows",
        as: SLSRequestNotificationsForWindowsFunction.self
    )

    // macOS 27 stopped posting the Dock's AXExpose* notifications. Mission Control's
    // WindowManager overlays remain observable without Screen Recording permission.
    private let windowManagerProcessName = "WindowManager"
    private let exposeShieldLevel = 19
    private let showDesktopOverlayLevel = 18
    private let spacesBarLevel = 14
    private let overlaySettleDelay: TimeInterval = 0.15
    private let overlayPollInterval: TimeInterval = 0.25

    private enum WindowServerEvent: UInt32, CaseIterable {
        case windowDestroyed = 804
        case windowCreated = 811
        case windowOrderedIn = 815
        case windowOrderedOut = 816
    }

    // MARK: - Public Interface

    func setHandler(_ handler: @escaping StateHandler) {
        self.handler = handler
    }

    func start() {
        guard !isMonitoring else { return }

        let isMacOS27OrLater = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        let isAXMonitoring = startAXMonitoring()

        let isOverlayMonitoring = isMacOS27OrLater ? startOverlayMonitoring() : false
        isOverlayStateAuthoritative = isMacOS27OrLater && isOverlayMonitoring

        guard isAXMonitoring || isOverlayMonitoring else {
            logger.error("Mission Control monitoring could not be started.")
            return
        }

        isMonitoring = true
        logger.info(
            "Mission Control monitoring started (AX: \(isAXMonitoring), overlay events: \(self.isOverlayEventMonitoring), overlay polling fallback: \(self.overlayPollTimer != nil))."
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
        isOverlayEventMonitoring = false
        isOverlayStateAuthoritative = false
        overlayUpdateWorkItem?.cancel()
        overlayUpdateWorkItem = nil
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

    fileprivate func axStateChanged(_ state: MissionControlState) {
        guard isOverlayStateAuthoritative else {
            notifyHandlerIfNeeded(newState: state)
            return
        }

        // AXExpose notifications can arrive out of order when Mission Control is closed and reopened quickly on macOS 27.
        // Reconcile them against the actual WindowManager surfaces instead of accepting the stale AX state.
        windowServerSurfacesChanged()
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

    private func startOverlayMonitoring() -> Bool {
        if registerWindowServerNotifications() {
            isOverlayEventMonitoring = true
            updateStateFromWindowManagerOverlays()
            if !subscribedWindowIDs.isEmpty {
                return true
            }

            isOverlayEventMonitoring = false
            logger.error("WindowServer window subscription failed, using polling fallback.")
        }

        // Keep the previous behavior as a compatibility fallback if the private WindowServer notification API is unavailable on a future macOS release.
        updateStateFromWindowManagerOverlays()
        let timer = Timer(timeInterval: overlayPollInterval, repeats: true) { [weak self] _ in
            self?.updateStateFromWindowManagerOverlays()
        }
        RunLoop.main.add(timer, forMode: .common)
        overlayPollTimer = timer
        return true
    }

    private func registerWindowServerNotifications() -> Bool {
        guard !areWindowServerNotificationsRegistered else { return true }
        guard let registerConnectionNotifyProc, requestNotificationsForWindows != nil else {
            logger.error("Required WindowServer notification APIs are unavailable.")
            return false
        }

        let connection = CGSMainConnectionID()
        let context = Unmanaged.passUnretained(self).toOpaque()
        var didRegisterAllEvents = true

        for event in WindowServerEvent.allCases {
            let result = registerConnectionNotifyProc(
                connection,
                windowServerNotificationCallback,
                event.rawValue,
                context
            )
            if result != .success {
                didRegisterAllEvents = false
                logger.error(
                    "Could not observe WindowServer event \(event.rawValue): \(result.rawValue).")
            }
        }

        areWindowServerNotificationsRegistered = didRegisterAllEvents
        return didRegisterAllEvents
    }

    fileprivate func windowServerSurfacesChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOverlayEventMonitoring else { return }

            self.overlayUpdateWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isOverlayEventMonitoring else { return }
                self.overlayUpdateWorkItem = nil
                self.updateStateFromWindowManagerOverlays()
            }
            self.overlayUpdateWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + self.overlaySettleDelay,
                execute: workItem
            )
        }
    }

    private func updateStateFromWindowManagerOverlays() {
        let windowList =
            CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] ?? []

        updateWindowServerSubscriptions(from: windowList)

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

    private func updateWindowServerSubscriptions(from windowList: [[String: Any]]) {
        guard isOverlayEventMonitoring, let requestNotificationsForWindows else { return }

        let currentProcessID = getpid()
        let windowIDs = Set(
            windowList.compactMap { window -> CGWindowID? in
                guard let windowID = window[kCGWindowNumber as String] as? CGWindowID,
                    let layer = window[kCGWindowLayer as String] as? Int
                else { return nil }

                let owner = window[kCGWindowOwnerName as String] as? String
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
                let isMissionControlSurface =
                    owner == windowManagerProcessName
                    && [exposeShieldLevel, showDesktopOverlayLevel, spacesBarLevel].contains(layer)

                // At least one subscribed window is required before WindowServer sends even connection-wide create/destroy events.
                // Regular windows seed delivery, detected Mission Control surfaces are added so their order-out event is also observed.
                return layer == 0 || ownerPID == currentProcessID || isMissionControlSurface
                    ? windowID : nil
            })

        guard !windowIDs.isEmpty, windowIDs != subscribedWindowIDs else { return }

        var list = Array(windowIDs)
        let result = requestNotificationsForWindows(
            CGSMainConnectionID(),
            &list,
            Int32(list.count)
        )
        if result == .success {
            subscribedWindowIDs = windowIDs
        } else {
            logger.error("Could not subscribe to WindowServer windows: \(result.rawValue).")
        }
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

// MARK: - WindowServer Callback

/// WindowServer invokes this on its notification thread. Keep the callback minimal and transfer state handling to the main queue before touching the monitor.
private let windowServerNotificationCallback: CGSConnectionNotifyProc = {
    _, _, _, context, _ in
    guard let context else { return }

    let monitor = Unmanaged<MissionControlMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.windowServerSurfacesChanged()
}

// MARK: - AXObserver Callback

/// Top-level C-compatible callback required by AXObserverCreate.
/// Recovers the `MissionControlMonitor` instance from `refcon` and
/// forwards the notification to the monitor's active state source.
private func axObserverCallback(
    _: AXObserver,
    _: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }

    let monitor = Unmanaged<MissionControlMonitor>.fromOpaque(refcon).takeUnretainedValue()

    if let state = MissionControlState(rawValue: notification as String) {
        monitor.axStateChanged(state)
    }
}
