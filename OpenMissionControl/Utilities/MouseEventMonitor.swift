//
//  MouseEventMonitor.swift
//  OpenMissionControl
//
//  Created by Travis XU on 15/3/2026.
//

import AppKit
import CoreGraphics
import Foundation
import os
import SwiftUI

/// Monitors global mouse events and notifies registered handlers on click and move events.
class MouseEventMonitor {
    static let shared = MouseEventMonitor()

    // MARK: - Types

    typealias ClickHandler = (_ location: CGPoint) -> Bool
    typealias MoveHandler = (_ location: CGPoint) -> Void
    typealias KeyHandler = (_ flags: CGEventFlags, _ keyCode: CGKeyCode) -> Bool

    // MARK: - Properties

    @AppStorage("mouseUpdateDuration") private var mouseUpdateDuration: Double = 0.1

    private let logger = Logger(
        subsystem: "dev.travisxu.OpenMissionControl",
        category: "MouseEventMonitor"
    )

    private var clickHandler: ClickHandler?
    private var moveHandler: MoveHandler?
    private var keyHandler: KeyHandler?
    private(set) var isMonitoring: Bool = false

    // MARK: - Click Monitoring (CGEvent tap)

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Move Monitoring (CGEvent polling)

    private var moveThread: Thread?
    private var stopMoveFlag: Bool = false

    // MARK: - Public Interface

    func setClickHandler(_ handler: @escaping ClickHandler) {
        clickHandler = handler
    }

    func setMoveHandler(_ handler: @escaping MoveHandler) {
        moveHandler = handler
    }

    func setKeyHandler(_ handler: @escaping KeyHandler) {
        keyHandler = handler
    }

    func start() {
        guard !isMonitoring else { return }

        isMonitoring = true

        startClickMonitoring()
        startMoveMonitoring()

        logger.info("Mouse event monitoring started.")
    }

    func stop() {
        guard isMonitoring else { return }

        stopClickMonitoring()
        stopMoveMonitoring()

        isMonitoring = false
        logger.info("Mouse event monitoring stopped.")
    }

    // MARK: - Private: Click Monitoring

    private func startClickMonitoring() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: mouseEventMonitorClickCallback,
            userInfo: nil
        ) else {
            logger.error("Failed to create click event tap. Please grant Accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Click event tap started.")
    }

    private func stopClickMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        logger.info("Click event tap stopped.")
    }

    // MARK: - Private: Move Monitoring

    // TODO: Performance optimizations (use event-based instead of pulling)
    private func startMoveMonitoring() {
        stopMoveFlag = false
        let thread = Thread { [weak self] in
            guard let self else { return }
            var lastLocation = CGPoint(x: -1, y: -1)
            while !self.stopMoveFlag {
                if let location = CGEvent(source: nil)?.location, location != lastLocation {
                    lastLocation = location
                    self.handleMove(to: location)
                }
                Thread.sleep(forTimeInterval: self.mouseUpdateDuration)
            }
        }
        thread.name = "MouseMovePoller"
        thread.qualityOfService = .userInteractive
        moveThread = thread
        thread.start()

        logger.info("Mouse move monitor started (CGEvent polling).")
    }

    private func stopMoveMonitoring() {
        stopMoveFlag = true
        moveThread = nil
        logger.info("Mouse move monitor stopped.")
    }

    // MARK: - Private Helpers

    /// Returns `true` if the event should be passed down the event chain, `false` to swallow it.
    @discardableResult
    fileprivate func handleClick(at location: CGPoint) -> Bool {
        return clickHandler?(location) ?? true
    }

    private func handleMove(to location: CGPoint) {
        moveHandler?(location)
    }

    @discardableResult
    fileprivate func handleKey(flags: CGEventFlags, keyCode: CGKeyCode) -> Bool {
        return keyHandler?(flags, keyCode) ?? true
    }

    // MARK: - Lifecycle

    deinit {
        stop()
    }
}

// MARK: - C Callback for Click Events

private func mouseEventMonitorClickCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon _: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if it was disabled by timeout or user input
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = MouseEventMonitor.shared.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if type == .leftMouseDown {
        let location = event.location
        let passDown = MouseEventMonitor.shared.handleClick(at: location)
        if !passDown {
            return nil
        }
    } else if type == .keyDown {
        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let passDown = MouseEventMonitor.shared.handleKey(flags: flags, keyCode: keyCode)
        if !passDown {
            return nil
        }
    }

    return Unmanaged.passRetained(event)
}
