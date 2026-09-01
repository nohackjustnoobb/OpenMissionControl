//
//  OpenMissionControlCore.swift
//  OpenMissionControl
//
//  Created by Travis XU on 13/3/2026.
//

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import SwiftUI
import os

@_silgen_name("CoreDockSendNotification")
func CoreDockSendNotification(_ notification: CFString, _ unknown: Int32) -> CGError

protocol DisplayNameable {
    var displayName: String { get }
}

enum WindowAction: Int, CaseIterable, DisplayNameable {
    case none = 0
    case minimize = 1
    case zoom = 2
    case close = 3
    case quit = 4

    var displayName: String {
        switch self {
        case .none: return "None"
        case .minimize: return "Minimize"
        case .zoom: return "Maximize"
        case .close: return "Close"
        case .quit: return "Quit"
        }
    }
}

enum WindowDragState: Int, CaseIterable {
    case none = 0
    case leftClickDownOnWindow = 1
    case leftClickDraggingWindow = 2
    case leftClickUpAfterDraggedWindow = 3
}

enum Instigator: Int, CaseIterable, DisplayNameable {
    case overlay
    case keyboard
    case mouse

    var displayName: String {
        switch self {
        case .overlay: return "Overlay Click"
        case .keyboard: return "Keyboard Shortcut"
        case .mouse: return "Mouse Shortcut"
        }
    }
}

final class OpenMissionControlCore: ObservableObject {
    static let shared = OpenMissionControlCore()
    private let logger = Logger(
        subsystem: "dev.travisxu.OpenMissionControl", category: "OpenMissionControlCore"
    )

    // MARK: - Window State

    private var windows: [[String: Any]] = []
    private var windowFetchTimer: Timer?
    @AppStorage(SettingsDefaults.Key.updateDuration) private var updateDuration: Double =
        SettingsDefaults.updateDuration
    @AppStorage(SettingsDefaults.Key.overlayButtonScale) private var overlayButtonScale: Double =
        SettingsDefaults.overlayButtonScale
    @AppStorage(SettingsDefaults.Key.restoreOverlayAfterDrag) private var restoreOverlayAfterDrag:
        Bool = SettingsDefaults.restoreOverlayAfterDrag
    @AppStorage(SettingsDefaults.Key.shortcutQuit) private var shortcutQuit: Bool =
        SettingsDefaults.shortcutQuit
    @AppStorage(SettingsDefaults.Key.shortcutClose) private var shortcutClose: Bool =
        SettingsDefaults.shortcutClose
    @AppStorage(SettingsDefaults.Key.shortcutMinimize) private var shortcutMinimize: Bool =
        SettingsDefaults.shortcutMinimize
    @AppStorage(SettingsDefaults.Key.shortcutMaximize) private var shortcutMaximize: Bool =
        SettingsDefaults.shortcutMaximize
    @AppStorage(SettingsDefaults.Key.shortcutActivateWindow) private var shortcutActivateWindow:
        Bool = SettingsDefaults.shortcutActivateWindow
    @AppStorage(SettingsDefaults.Key.rightClickAction) private var rightClickAction: WindowAction =
        SettingsDefaults.rightClickAction
    @AppStorage(SettingsDefaults.Key.middleClickAction) private var middleClickAction:
        WindowAction =
            SettingsDefaults.middleClickAction

    // MARK: - Lifecycle

    @Published private(set) var isRunning: Bool = false
    private var axTrustedTimer: Timer?
    private var wasAXTrusted: Bool = AXIsProcessTrusted()

    func start() {
        guard !isRunning else { return }

        isRunning = true

        wasAXTrusted = AXIsProcessTrusted()
        axTrustedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            let isTrusted = AXIsProcessTrusted()
            if let self = self {
                if !self.wasAXTrusted, isTrusted {
                    self.restartApp()
                }
                self.wasAXTrusted = isTrusted
            }
        }

        // Configure Mission Control monitor
        MissionControlMonitor.shared.setHandler { [weak self] state in
            DispatchQueue.main.async {
                self?.handleMissionControlStateChange(state)
            }
        }
        MissionControlMonitor.shared.start()

        // Configure input event monitor
        InputEventMonitor.shared.setClickHandler { [weak self] location, button in
            guard let self = self else { return true }

            self.logger.debug(
                "Mouse clicked at: \(location.x), \(location.y) (button: \(button.rawValue))")
            return self.handleMouseClick(at: location, with: button)
        }
        InputEventMonitor.shared.setDragHandler { [weak self] location, button in
            guard let self = self else { return }

            self.handleMouseDrag(at: location, with: button)
        }
        InputEventMonitor.shared.setMouseUpHandler { [weak self] location, button in
            guard let self = self else { return true }

            return self.handleMouseUp(at: location, with: button)
        }
        InputEventMonitor.shared.setMoveHandler { [weak self] location in
            guard let self = self else { return }

            self.logger.debug("Mouse moved to: \(location.x), \(location.y)")
            self.handleMouseMove(to: location)
        }
        InputEventMonitor.shared.setKeyHandler { [weak self] flags, keyCode in
            guard let self = self else { return true }

            return self.handleKeyPress(flags: flags, keyCode: keyCode)
        }

        // Listen for active space changes to refresh window list and overlay
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        logger.info("OpenMissionControlCore started.")
    }

    func stop() {
        axTrustedTimer?.invalidate()
        axTrustedTimer = nil
        MissionControlMonitor.shared.stop()
        InputEventMonitor.shared.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        hideOverlay()
        isRunning = false

        logger.info("OpenMissionControlCore stopped.")
    }

    deinit {
        stop()
    }

    // MARK: - Mission Control State

    private func handleMissionControlStateChange(_ state: MissionControlState) {
        logger.info("Mission Control state changed: \(state.rawValue)")

        if state.isActive {
            isOverlayShown = true
            showOverlay()
        } else {
            isOverlayShown = false
            hideOverlay()
        }
    }

    // MARK: - Active Space Change Handling

    @objc private func activeSpaceDidChange() {
        guard isOverlayShown else { return }

        logger.info("Active space changed, recreating windows and overlay.")

        recreateOverlay()
    }

    // MARK: - Mouse Event Handling

    @discardableResult
    private func handleMouseClick(at location: CGPoint, with button: CGMouseButton) -> Bool {
        guard isOverlayShown else { return true }

        if let rect = overlayRect, rect.contains(location) {
            if button == .left {
                logger.debug(
                    "Captured left click inside overlayRect at (\(location.x), \(location.y)).")
                handleOverlayClick(at: location)
                return false
            } else {
                logger.debug(
                    "Captured non-left click inside overlayRect at (\(location.x), \(location.y)), skipping."
                )
                return true
            }
        }

        if let window = hoveredWindow {
            switch button {
            case .left:
                logger.debug(
                    "Captured left click on hovered window at (\(location.x), \(location.y)).")
                if restoreOverlayAfterDrag {
                    windowDragState = .leftClickDownOnWindow
                    hideOverlay(keepInputMonitoring: true)
                } else {
                    hideOverlay()
                }
                return true
            case .right:
                logger.debug(
                    "Captured right click on hovered window at (\(location.x), \(location.y)).")
                performWindowAction(window: window, action: rightClickAction, instigator: .mouse)
                return rightClickAction == .none
            case .center:
                logger.debug(
                    "Captured middle click on hovered window at (\(location.x), \(location.y)).")
                performWindowAction(window: window, action: middleClickAction, instigator: .mouse)
                return middleClickAction == .none
            default:
                logger.debug(
                    "Captured non-default click (id \(button.rawValue)) on hovered window at (\(location.x), \(location.y)), skipping."
                )
                return true
            }
        }

        hideOverlay()
        return true
    }

    private func handleMouseMove(to location: CGPoint) {
        guard windowDragState == .none else { return }

        updateOverlay(at: location)
    }

    private func handleMouseDrag(at _: CGPoint, with button: CGMouseButton) {
        guard button == .left, windowDragState == .leftClickDownOnWindow else { return }

        logger.debug("Mouse started dragging the clicked window.")
        windowDragState = .leftClickDraggingWindow
    }

    @discardableResult
    private func handleMouseUp(at _: CGPoint, with button: CGMouseButton) -> Bool {
        guard button == .left, windowDragState != .none else { return true }

        let shouldRestoreOverlay = windowDragState == .leftClickDraggingWindow
        if shouldRestoreOverlay, isOverlayShown {
            logger.debug("Mouse released the dragged window, restoring overlay.")
            windowDragState = .leftClickUpAfterDraggedWindow
            recreateOverlay()
        } else {
            windowDragState = .none
        }

        return true
    }

    // MARK: - Key Event Handling

    private func handleKeyPress(flags: CGEventFlags, keyCode: CGKeyCode) -> Bool {
        guard isOverlayShown else { return true }

        let isReturnKey =
            keyCode == KeyboardKey.return.rawValue
            || keyCode == KeyboardKey.keypadEnter.rawValue
        let hasActionModifier =
            flags.contains(.maskCommand) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate) || flags.contains(.maskShift)

        if shortcutActivateWindow, isReturnKey, !hasActionModifier {
            if let window = hoveredWindow {
                activateHoveredWindow(window)
            }
            return false
        }

        guard let window = hoveredWindow else { return true }

        // Check for Command key
        guard flags.contains(.maskCommand) else { return true }

        switch KeyboardKey(rawValue: keyCode) {
        case .q:
            if shortcutQuit {
                performWindowAction(window: window, action: .quit, instigator: .keyboard)
                return false
            }
        case .w:
            if shortcutClose {
                performWindowAction(window: window, action: .close, instigator: .keyboard)
                return false
            }
        case .m:
            if shortcutMinimize {
                performWindowAction(window: window, action: .minimize, instigator: .keyboard)
                return false
            }
        case .f:
            if shortcutMaximize {
                performWindowAction(window: window, action: .zoom, instigator: .keyboard)
                return false
            }
        default:
            break
        }

        return true
    }

    private func activateHoveredWindow(_ window: [String: Any]) {
        guard let location = CGEvent(source: nil)?.location else { return }

        let windowName = window[kCGWindowName as String] as? String ?? ""
        logger.info("Return shortcut activated window: \(windowName)")

        hideOverlay()

        let source = CGEventSource(stateID: .hidSystemState)
        let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: location,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        )
        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Window Fetching

    func fetchWindows() {
        let windowList =
            CGWindowListCopyWindowInfo(
                CGWindowListOption.optionOnScreenOnly,
                kCGNullWindowID
            ) as? [[String: Any]] ?? []

        let filteredWindows = windowList.filter { window in
            window[kCGWindowLayer as String] as? Int == 0
        }

        let regularWindows = filteredWindows.filter {
            ($0[kCGWindowOwnerName as String] as? String) != "Dock"
        }

        DispatchQueue.main.async {
            let areEqual = NSArray(array: self.windows).isEqual(to: regularWindows)
            if !areEqual {
                // Debug output
                self.logger.debug("=== Windows (\(filteredWindows.count)) ===")
                for (index, window) in filteredWindows.enumerated() {
                    let name = window[kCGWindowName as String] as? String ?? "Unknown"
                    let owner = window[kCGWindowOwnerName as String] as? String ?? "Unknown"
                    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
                    self.logger.debug(
                        "[\(index)] \(owner) - \(name) | bounds: \(String(describing: bounds))"
                    )
                }

                self.windows = regularWindows
            }
        }
    }

    // MARK: - Overlay Management

    private var overlayWindow: NSWindow?
    private(set) var overlayRect: CGRect?
    private(set) var hoveredWindow: [String: Any]?
    private var windowDragState: WindowDragState = .none

    @Published private(set) var isOverlayShown: Bool = false
    @Published private(set) var isOverlayHovered: Bool = false

    func updateOverlay(at mouseLocation: CGPoint) {
        guard isOverlayShown else {
            return
        }

        DispatchQueue.main.async { [self] in
            if let rect = overlayRect {
                let isHovering = hoveredWindow != nil && rect.contains(mouseLocation)
                if isOverlayHovered != isHovering {
                    isOverlayHovered = isHovering
                }
                if isHovering {
                    return
                }
            }

            // Find window under mouse
            for windowInfo in windows {
                guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                    let x = boundsDict["X"],
                    let y = boundsDict["Y"],
                    let width = boundsDict["Width"],
                    let height = boundsDict["Height"]
                else {
                    continue
                }

                let windowFrame = CGRect(x: x, y: y, width: width, height: height)

                // Check if mouse is within this window's bounds
                if windowFrame.contains(mouseLocation) {
                    // Convert CG top-left coordinates to NSWindow bottom-left coordinates
                    let screenHeight =
                        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
                    let sizing = OverlaySizing(scale: overlayButtonScale)
                    let convertedY = screenHeight - y - sizing.height

                    let showQuit =
                        UserDefaults.standard.object(forKey: SettingsDefaults.Key.showQuitButton)
                        as? Bool ?? SettingsDefaults.showQuitButton
                    let showClose =
                        UserDefaults.standard.object(forKey: SettingsDefaults.Key.showCloseButton)
                        as? Bool ?? SettingsDefaults.showCloseButton
                    let showMinimize =
                        UserDefaults.standard.object(
                            forKey: SettingsDefaults.Key.showMinimizeButton
                        ) as? Bool
                        ?? SettingsDefaults.showMinimizeButton
                    let showZoom =
                        UserDefaults.standard.object(forKey: SettingsDefaults.Key.showZoomButton)
                        as? Bool ?? SettingsDefaults.showZoomButton
                    let buttonCount = [showQuit, showClose, showMinimize, showZoom].filter { $0 }
                        .count
                    let overlayWidth = sizing.width(buttonCount: buttonCount)

                    let newFrame = NSRect(
                        x: x + 8, y: convertedY - 8, width: overlayWidth, height: sizing.height
                    )
                    overlayWindow?.setFrame(newFrame, display: true)
                    overlayWindow?.orderFront(nil)

                    let cgOverlayRect = CGRect(
                        x: x + 8, y: y + 8, width: overlayWidth, height: sizing.height
                    )
                    overlayRect = cgOverlayRect
                    hoveredWindow = windowInfo

                    overlayWindow?.orderFront(nil)
                    return
                }
            }

            hoveredWindow = nil
            overlayWindow?.orderOut(nil)
        }
    }

    func handleOverlayClick(at location: CGPoint) {
        guard let rect = overlayRect, let window = hoveredWindow else { return }

        let localX = location.x - rect.minX
        let sizing = OverlaySizing(scale: overlayButtonScale)
        var currentX = sizing.horizontalPadding

        let showQuit =
            UserDefaults.standard.object(forKey: SettingsDefaults.Key.showQuitButton) as? Bool
            ?? SettingsDefaults.showQuitButton
        let showClose =
            UserDefaults.standard.object(forKey: SettingsDefaults.Key.showCloseButton) as? Bool
            ?? SettingsDefaults.showCloseButton
        let showMinimize =
            UserDefaults.standard.object(forKey: SettingsDefaults.Key.showMinimizeButton) as? Bool
            ?? SettingsDefaults.showMinimizeButton
        let showZoom =
            UserDefaults.standard.object(forKey: SettingsDefaults.Key.showZoomButton) as? Bool
            ?? SettingsDefaults.showZoomButton

        if showQuit {
            if localX >= currentX, localX <= currentX + sizing.buttonSize {
                performWindowAction(window: window, action: .quit, instigator: .overlay)
            }
            currentX += sizing.buttonStride
        }

        if showClose {
            if localX >= currentX, localX <= currentX + sizing.buttonSize {
                performWindowAction(window: window, action: .close, instigator: .overlay)
            }
            currentX += sizing.buttonStride
        }

        if showMinimize {
            if localX >= currentX, localX <= currentX + sizing.buttonSize {
                performWindowAction(window: window, action: .minimize, instigator: .overlay)
            }
            currentX += sizing.buttonStride
        }

        if showZoom {
            if localX >= currentX, localX <= currentX + sizing.buttonSize {
                performWindowAction(window: window, action: .zoom, instigator: .overlay)
            }
            currentX += sizing.buttonStride
        }
    }

    private func performWindowAction(
        window: [String: Any], action: WindowAction, instigator: Instigator
    ) {
        let windowName = window[kCGWindowName as String] as? String ?? ""

        switch action {
        case .quit:
            logger.info("\(instigator.displayName) Quit triggered on window: \(windowName)")
            quitApplication(window: window)
        case .minimize:
            logger.info("\(instigator.displayName) Minimize triggered on window: \(windowName)")
            performOSWindowAction(window: window, action: kAXMinimizeButtonAttribute)
        case .zoom:
            logger.info("\(instigator.displayName) Maximize triggered on window: \(windowName)")
            _ = CoreDockSendNotification("com.apple.expose.awake" as CFString, 0)
            hideOverlay()
            performOSWindowAction(window: window, action: kAXZoomButtonAttribute)
        case .close:
            logger.info("\(instigator.displayName) Close triggered on window: \(windowName)")
            performOSWindowAction(window: window, action: kAXCloseButtonAttribute)
        default:
            break
        }
    }

    private func performOSWindowAction(window: [String: Any], action: String) {
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
            let windowID = window[kCGWindowNumber as String] as? CGWindowID
        else {
            logger.error("Failed to get PID or WindowID for window: \(window)")
            return
        }

        let app = AXUIElementCreateApplication(pid)
        let windows = (try? app.windows()) ?? []
        logger.debug("AXUIElement windows for PID \(pid): \(windows.count)")

        for axWindow in windows {
            if let axWindowId = try? axWindow.cgWindowId(), axWindowId == windowID {
                do {
                    if let button = try? axWindow.attribute(action, AXUIElement.self) {
                        try button.performAction(kAXPressAction)
                        logger.info(
                            "Performed \(action) on window with PID \(pid) and WindowID \(windowID)"
                        )
                    } else {
                        logger.error(
                            "Failed to get \(action) for window with PID \(pid) and WindowID \(windowID)"
                        )
                    }
                } catch {
                    logger.error(
                        "Failed to perform action \(action) on window: \(error.localizedDescription)"
                    )
                }

                return
            }
        }

        logger.warning(
            "No matching AXUIElement found for window with PID \(pid) and WindowID \(windowID)"
        )
    }

    private func quitApplication(window: [String: Any]) {
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t else {
            logger.error("Failed to get PID for window: \(window)")
            return
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
            logger.info("Terminated application with PID \(pid)")
        } else {
            logger.error("Failed to get NSRunningApplication for PID \(pid)")
        }
    }

    func showOverlay() {
        // TODO: Optimize by only fetching windows when necessary
        if windowFetchTimer == nil {
            fetchWindows()

            windowFetchTimer = Timer.scheduledTimer(withTimeInterval: updateDuration, repeats: true)
            { [weak self] _ in
                self?.fetchWindows()
            }
        }

        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OverlayView())
            overlayWindow = window
        }

        // Start mouse monitoring when overlay is visible
        InputEventMonitor.shared.start()

        // Do an initial overlay update with current mouse position.
        // (Skip the update after a window drag to ensure that the overlay doesn't
        // get shown immediately at the coordinates where the drag ended, because
        // this would result in rendering the overlay at invalid position.)
        if windowDragState == .none {
            if let mouseLocation = CGEvent(source: nil)?.location {
                updateOverlay(at: mouseLocation)
            }
        } else {
            windowDragState = .none
        }
    }

    func hideOverlay(keepInputMonitoring: Bool = false) {
        windowFetchTimer?.invalidate()
        windowFetchTimer = nil
        overlayWindow?.orderOut(nil)
        hoveredWindow = nil
        isOverlayHovered = false

        if keepInputMonitoring {
            return
        }

        windowDragState = .none
        InputEventMonitor.shared.stop()
    }

    func recreateOverlay() {
        overlayWindow?.close()
        overlayWindow = nil

        showOverlay()
    }

    private func restartApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }
}
