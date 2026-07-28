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
import os
import SwiftUI

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

/// A user-selectable extra key for Mission Control keyboard navigation. The raw value is the
/// macOS virtual keycode of each letter (which are not alphabetical), so `keyCode` maps directly.
/// `.none` disables the extra key. Cases are declared alphabetically for a tidy picker order.
enum NavigationKey: Int, CaseIterable, DisplayNameable {
    case none = -1
    case a = 0
    case b = 11
    case c = 8
    case d = 2
    case e = 14
    case f = 3
    case g = 5
    case h = 4
    case i = 34
    case j = 38
    case k = 40
    case l = 37
    case m = 46
    case n = 45
    case o = 31
    case p = 35
    case q = 12
    case r = 15
    case s = 1
    case t = 17
    case u = 32
    case v = 9
    case w = 13
    case x = 7
    case y = 16
    case z = 6

    var displayName: String {
        self == .none ? "None" : String(describing: self).uppercased()
    }

    /// The virtual keycode this key represents, or `nil` when disabled (`.none`).
    var keyCode: CGKeyCode? {
        self == .none ? nil : CGKeyCode(rawValue)
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

    /// Index into `sortedWindows` of the keyboard-selected window. `-1` means no keyboard
    /// selection yet — the sentinel that keeps mouse-only usage untouched until the first Tab.
    private var selectedIndex: Int = -1
    @AppStorage(SettingsDefaults.Key.updateDuration) private var updateDuration: Double =
        SettingsDefaults.updateDuration
    @AppStorage(SettingsDefaults.Key.shortcutQuit) private var shortcutQuit: Bool =
        SettingsDefaults.shortcutQuit
    @AppStorage(SettingsDefaults.Key.shortcutClose) private var shortcutClose: Bool =
        SettingsDefaults.shortcutClose
    @AppStorage(SettingsDefaults.Key.shortcutMinimize) private var shortcutMinimize: Bool =
        SettingsDefaults.shortcutMinimize
    @AppStorage(SettingsDefaults.Key.shortcutMaximize) private var shortcutMaximize: Bool =
        SettingsDefaults.shortcutMaximize
    @AppStorage(SettingsDefaults.Key.keyboardNavigation) private var keyboardNavigation: Bool =
        SettingsDefaults.keyboardNavigation
    @AppStorage(SettingsDefaults.Key.tabNavigationExtraKey) private var tabNavigationExtraKey:
        NavigationKey = SettingsDefaults.tabNavigationExtraKey
    @AppStorage(SettingsDefaults.Key.enterNavigationExtraKey) private var enterNavigationExtraKey:
        NavigationKey = SettingsDefaults.enterNavigationExtraKey
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

        // Configure mouse event monitor
        MouseEventMonitor.shared.setClickHandler { [weak self] location, button in
            guard let self = self else { return true }

            self.logger.debug("Mouse clicked at: \(location.x), \(location.y) (button: \(button.rawValue))")
            return self.handleMouseClick(at: location, with: button)
        }
        MouseEventMonitor.shared.setMoveHandler { [weak self] location in
            guard let self = self else { return }

            self.logger.debug("Mouse moved to: \(location.x), \(location.y)")
            self.handleMouseMove(to: location)
        }
        MouseEventMonitor.shared.setKeyHandler { [weak self] flags, keyCode in
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
        MouseEventMonitor.shared.stop()
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
            selectedIndex = -1
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

        selectedIndex = -1
        recreateOverlay()
    }

    // MARK: - Mouse Event Handling

    @discardableResult
    private func handleMouseClick(at location: CGPoint, with button: CGMouseButton) -> Bool {
        guard isOverlayShown else { return true }

        if let rect = overlayRect, rect.contains(location) {
            if button == .left {
                logger.debug("Captured left click inside overlayRect at (\(location.x), \(location.y)).")
                handleOverlayClick(at: location)
                return false
            } else {
                logger.debug("Captured non-left click inside overlayRect at (\(location.x), \(location.y)), skipping.")
                return true
            }
        }

        if let window = hoveredWindow {
            switch button {
            case .left:
                logger.debug("Captured left click on hovered window at (\(location.x), \(location.y)).")
                hideOverlay()
                return true
            case .right:
                logger.debug("Captured right click on hovered window at (\(location.x), \(location.y)).")
                performWindowAction(window: window, action: rightClickAction, instigator: .mouse)
                return rightClickAction == .none
            case .center:
                logger.debug("Captured middle click on hovered window at (\(location.x), \(location.y)).")
                performWindowAction(window: window, action: middleClickAction, instigator: .mouse)
                return middleClickAction == .none
            default:
                logger.debug("Captured non-default click (id \(button.rawValue)) on hovered window at (\(location.x), \(location.y)), skipping.")
                return true
            }
        }

        return true
    }

    private func handleMouseMove(to location: CGPoint) {
        updateOverlay(at: location)
    }

    // MARK: - Key Event Handling

    private func handleKeyPress(flags: CGEventFlags, keyCode: CGKeyCode) -> Bool {
        guard isOverlayShown else { return true }

        // Keyboard navigation: Tab / Shift+Tab cycle the selection, Return / Enter activates it.
        // No modifier is required, so this must be handled before the Command-shortcut path below.
        // Command is explicitly excluded so ⌘Tab (app switcher) keeps passing through untouched.
        if keyboardNavigation, !flags.contains(.maskCommand) {
            // Tab and Return/Enter are always active; the extra keys are user-configurable
            // (default D to rotate, K to activate). If both map to the same key, rotate wins.
            if keyCode == 48 || tabNavigationExtraKey.keyCode == keyCode {
                moveSelection(by: flags.contains(.maskShift) ? -1 : 1)
                return false
            }
            if keyCode == 36 || keyCode == 76 || enterNavigationExtraKey.keyCode == keyCode {
                activateSelection()
                return false
            }
        }

        // Command-modified window actions operate on the hovered (or keyboard-selected) window.
        guard let window = hoveredWindow else { return true }
        guard flags.contains(.maskCommand) else { return true }

        switch keyCode {
        case 12: // Q
            if shortcutQuit {
                performWindowAction(window: window, action: .quit, instigator: .keyboard)
                return false
            }
        case 13: // W
            if shortcutClose {
                performWindowAction(window: window, action: .close, instigator: .keyboard)
                return false
            }
        case 46: // M
            if shortcutMinimize {
                performWindowAction(window: window, action: .minimize, instigator: .keyboard)
                return false
            }
        case 3: // F
            if shortcutMaximize {
                performWindowAction(window: window, action: .zoom, instigator: .keyboard)
                return false
            }
        default:
            break
        }

        return true
    }

    // MARK: - Keyboard Navigation

    private func frame(of window: [String: Any]) -> CGRect? {
        guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let w = bounds["Width"], let h = bounds["Height"]
        else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The point used to hover and click a thumbnail. Near the top-left corner rather than the
    /// center: with "group windows by application", thumbnails stack and each front window hides
    /// the center of the one behind it, so a center point can never reach the back windows. The
    /// exposed top-left "shoulder" of each stacked window is unique to it. Kept below OMC's own
    /// button overlay (top-left, ~48pt tall) so activating never accidentally presses a button.
    private func selectionPoint(for frame: CGRect) -> CGPoint {
        return CGPoint(x: frame.minX + 24, y: frame.minY + 64)
    }

    /// Windows ordered for Tab traversal: row first (top to bottom), then column (left to right).
    /// More predictable visually than the z-order that `CGWindowListCopyWindowInfo` returns.
    ///
    /// Rows are built greedily from a stable top-to-bottom sort: a thumbnail joins the current
    /// row when its top is within `rowTolerance` of that row's top, otherwise it starts a new row.
    /// This is a deterministic total order — unlike a direct `abs(dy) > tol` comparator, which is
    /// not a strict weak ordering and yields an unspecified result from `sorted`. Tune `rowTolerance`
    /// if the tab order looks off.
    private var sortedWindows: [[String: Any]] {
        let rowTolerance: CGFloat = 50

        let framed = windows.compactMap { win -> (win: [String: Any], frame: CGRect)? in
            guard let f = frame(of: win) else { return nil }
            return (win, f)
        }
        .sorted { $0.frame.minY < $1.frame.minY }

        var rows: [[(win: [String: Any], frame: CGRect)]] = []
        for item in framed {
            if let rowTop = rows.last?.first?.frame.minY,
               abs(item.frame.minY - rowTop) <= rowTolerance {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }

        return rows.flatMap { row in
            row.sorted { $0.frame.minX < $1.frame.minX }.map(\.win)
        }
    }

    /// Moves the keyboard selection by `delta` (with wrap-around) and posts a synthetic
    /// `.mouseMoved` to the selected thumbnail's center. Mission Control then draws its own
    /// native highlight, and `hoveredWindow` syncs so the ⌘Q/W/M/F shortcuts keep working
    /// against the keyboard selection without any change to their switch.
    private func moveSelection(by delta: Int) {
        let list = sortedWindows
        guard !list.isEmpty else { return }

        selectedIndex = selectedIndex < 0
            ? (delta > 0 ? 0 : list.count - 1)
            : ((selectedIndex + delta) % list.count + list.count) % list.count

        guard let f = frame(of: list[selectedIndex]) else { return }
        let pt = selectionPoint(for: f)

        // NB: `.mouseMoved` (not CGWarpMouseCursorPosition) — Mission Control only repaints its
        // highlight in response to an actual move event.
        CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: pt, mouseButton: .left
        )?.post(tap: .cghidEventTap)

        updateOverlay(at: pt) // sync hoveredWindow immediately instead of waiting for the poller
    }

    /// Activates the current keyboard selection by posting a synthetic left click on its
    /// thumbnail center. The click flows through the normal `handleMouseClick` path, which
    /// hides the overlay and lets Mission Control raise the window and dismiss itself.
    private func activateSelection() {
        let list = sortedWindows
        guard selectedIndex >= 0, selectedIndex < list.count,
              let f = frame(of: list[selectedIndex]) else { return }
        let pt = selectionPoint(for: f)

        let post: (CGEventType) -> Void = { type in
            CGEvent(
                mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: pt, mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }

        // Land Mission Control's hover on this thumbnail, then click it. The mouseUp is delayed:
        // a zero-duration synthetic click is unreliably registered by Mission Control as a
        // selection. The click flows through handleMouseClick, which raises the window.
        post(.mouseMoved)
        post(.leftMouseDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            post(.leftMouseUp)
        }
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

    @Published private(set) var isOverlayShown: Bool = false
    @Published private(set) var isOverlayHovered: Bool = false

    func updateOverlay(at mouseLocation: CGPoint) {
        guard isOverlayShown else {
            return
        }

        DispatchQueue.main.async { [self] in
            if let rect = overlayRect {
                let isHovering = rect.contains(mouseLocation)
                if isOverlayHovered != isHovering {
                    isOverlayHovered = isHovering
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
                    let convertedY = screenHeight - y - 40

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
                    let overlayWidth = CGFloat(12 + buttonCount * 32)

                    let newFrame = NSRect(
                        x: x + 8, y: convertedY - 8, width: overlayWidth, height: 40
                    )
                    overlayWindow?.setFrame(newFrame, display: true)
                    overlayWindow?.orderFront(nil)

                    let cgOverlayRect = CGRect(x: x + 8, y: y + 8, width: overlayWidth, height: 40)
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
        var currentX: CGFloat = 8

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
            if localX >= currentX, localX <= currentX + 24 {
                performWindowAction(window: window, action: .quit, instigator: .overlay)
            }
            currentX += 32
        }

        if showClose {
            if localX >= currentX, localX <= currentX + 24 {
                performWindowAction(window: window, action: .close, instigator: .overlay)
            }
            currentX += 32
        }

        if showMinimize {
            if localX >= currentX, localX <= currentX + 24 {
                performWindowAction(window: window, action: .minimize, instigator: .overlay)
            }
            currentX += 32
        }

        if showZoom {
            if localX >= currentX, localX <= currentX + 24 {
                performWindowAction(window: window, action: .zoom, instigator: .overlay)
            }
            currentX += 32
        }
    }

    private func performWindowAction(window: [String: Any], action: WindowAction, instigator: Instigator) {
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

            windowFetchTimer = Timer.scheduledTimer(withTimeInterval: updateDuration, repeats: true) { [weak self] _ in
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
        MouseEventMonitor.shared.start()

        // Do an initial overlay update with current mouse position
        if let mouseLocation = CGEvent(source: nil)?.location {
            updateOverlay(at: mouseLocation)
        }
    }

    func hideOverlay() {
        windowFetchTimer?.invalidate()
        windowFetchTimer = nil
        overlayWindow?.orderOut(nil)
        MouseEventMonitor.shared.stop()
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
