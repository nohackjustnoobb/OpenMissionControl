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

final class OpenMissionControlCore: ObservableObject {
    static let shared = OpenMissionControlCore()
    private let logger = Logger(subsystem: "dev.travisxu.OpenMissionControl", category: "OpenMissionControlCore")

    // MARK: - Published Properties

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isOverlayShown: Bool = false
    @Published private(set) var isOverlayHovered: Bool = false

    // MARK: - Window State

    private var windows: [[String: Any]] = []

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        isRunning = true

        // Configure Mission Control monitor
        MissionControlMonitor.shared.setHandler { [weak self] state in
            DispatchQueue.main.async {
                self?.handleMissionControlStateChange(state)
            }
        }
        MissionControlMonitor.shared.start()

        // Configure mouse event monitor
        MouseEventMonitor.shared.setClickHandler { [weak self] location in
            guard let self = self else { return true }

            self.logger.debug("Mouse clicked at: \(location.x), \(location.y)")
            return self.handleMouseClick(at: location)
        }
        MouseEventMonitor.shared.setMoveHandler { [weak self] location in
            guard let self = self else { return }

            self.logger.debug("Mouse moved to: \(location.x), \(location.y)")
            self.handleMouseMove(to: location)
        }

        logger.info("OpenMissionControlCore started.")
    }

    func stop() {
        MissionControlMonitor.shared.stop()
        MouseEventMonitor.shared.stop()
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
            fetchWindows()
            isOverlayShown = true
            showOverlay()
        } else {
            isOverlayShown = false
            hideOverlay()
        }
    }

    // MARK: - Mouse Event Handling

    @discardableResult
    private func handleMouseClick(at location: CGPoint) -> Bool {
        guard isOverlayShown else { return true }

        if let rect = overlayRect, rect.contains(location) {
            logger.debug("Captured left click inside overlayRect at (\(location.x), \(location.y))")
            handleOverlayClick(at: location)
            return false
        }

        return true
    }

    private func handleMouseMove(to location: CGPoint) {
        guard isOverlayShown else { return }

        updateOverlay(at: location)
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

        // Debug output
        logger.debug("=== Windows (\(filteredWindows.count)) ===")
        for (index, window) in filteredWindows.enumerated() {
            let name = window[kCGWindowName as String] as? String ?? "Unknown"
            let owner = window[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            logger.debug("[\(index)] \(owner) - \(name) | bounds: \(String(describing: bounds))")
        }

        let regularWindows = filteredWindows.filter {
            ($0[kCGWindowOwnerName as String] as? String) != "Dock"
        }

        DispatchQueue.main.async {
            self.windows = regularWindows
        }
    }

    // MARK: - Overlay Management

    private var overlayWindow: NSWindow?
    private(set) var overlayRect: CGRect?
    private(set) var hoveredWindow: [String: Any]?

    func updateOverlay(at mouseLocation: CGPoint) {
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
                    let screenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
                    let convertedY = screenHeight - y - 40

                    let newFrame = NSRect(x: x + 8, y: convertedY - 8, width: 104, height: 40)
                    overlayWindow?.setFrame(newFrame, display: true)
                    overlayWindow?.orderFront(nil)

                    let cgOverlayRect = CGRect(x: x + 8, y: y + 8, width: 104, height: 40)
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

        let showClose = UserDefaults.standard.object(forKey: "showCloseButton") as? Bool ?? true
        let showMinimize = UserDefaults.standard.object(forKey: "showMinimizeButton") as? Bool ?? true
        let showZoom = UserDefaults.standard.object(forKey: "showZoomButton") as? Bool ?? true

        let windowName = window[kCGWindowName as String] as? String ?? ""

        if showClose {
            if localX >= currentX, localX <= currentX + 24 {
                logger.info("Close button clicked on window: \(windowName)")
                performWindowAction(window: window, action: kAXCloseButtonAttribute)
            }
            currentX += 32
        }

        if showMinimize {
            if localX >= currentX, localX <= currentX + 24 {
                logger.info("Minimize button clicked on window: \(windowName)")
                performWindowAction(window: window, action: kAXMinimizeButtonAttribute)
            }
            currentX += 32
        }

        if showZoom {
            if localX >= currentX, localX <= currentX + 24 {
                logger.info("Zoom button clicked on window: \(windowName)")
                _ = CoreDockSendNotification("com.apple.expose.awake" as CFString, 0)
                performWindowAction(window: window, action: kAXZoomButtonAttribute)
            }
            currentX += 32
        }
    }

    private func performWindowAction(window: [String: Any], action: String) {
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
                    }
                } catch {
                    logger.error("Failed to perform action \(action) on window: \(error.localizedDescription)")
                }
                return
            }
        }

        logger.warning("No matching AXUIElement found for window with PID \(pid) and WindowID \(windowID)")
    }

    func showOverlay() {
        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
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
        overlayWindow?.orderOut(nil)
        MouseEventMonitor.shared.stop()
    }
}
