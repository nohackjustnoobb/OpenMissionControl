//
//  InputEventMonitor.swift
//  OpenMissionControl
//
//  Created by Travis XU on 15/3/2026.
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import os

/// Monitors global input events and notifies registered handlers on click, move, and key events.
class InputEventMonitor {
    static let shared = InputEventMonitor()

    // MARK: - Types

    typealias ClickHandler = (_ location: CGPoint, _ buttonCode: CGMouseButton) -> Bool
    typealias MoveHandler = (_ location: CGPoint) -> Void
    typealias KeyHandler = (_ flags: CGEventFlags, _ keyCode: CGKeyCode) -> Bool

    // MARK: - Properties

    @AppStorage(SettingsDefaults.Key.mouseUpdateDuration) private var mouseUpdateDuration: Double =
        SettingsDefaults.mouseUpdateDuration

    private let logger = Logger(
        subsystem: "dev.travisxu.OpenMissionControl",
        category: "InputEventMonitor"
    )

    private var clickHandler: ClickHandler?
    private var moveHandler: MoveHandler?
    private var keyHandler: KeyHandler?
    private(set) var isMonitoring: Bool = false

    // MARK: - Input Monitoring (CGEvent tap)

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Move Monitoring (NSEvent)

    private var mouseMoveMonitor: Any?
    private var lastMoveEventTimestamp: TimeInterval = 0

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
        lastMoveEventTimestamp = 0

        startInputMonitoring()
        startMoveMonitoring()

        logger.info("Input event monitoring started.")
    }

    func stop() {
        guard isMonitoring else { return }

        stopMoveMonitoring()
        stopInputMonitoring()
        lastMoveEventTimestamp = 0

        isMonitoring = false
        logger.info("Input event monitoring stopped.")
    }

    // MARK: - Private: Input Monitoring

    private func startInputMonitoring() {
        let eventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: inputEventMonitorCallback,
                userInfo: nil
            )
        else {
            logger.error(
                "Failed to create input event tap. Please grant Accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Input event tap started.")
    }

    private func stopInputMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        logger.info("Input event tap stopped.")
    }

    // MARK: - Private: Move Monitoring

    private func startMoveMonitoring() {
        guard mouseMoveMonitor == nil else { return }

        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
            [weak self] event in
            guard let self, let cgEvent = event.cgEvent else { return }

            self.handleMove(to: cgEvent.location, timestamp: event.timestamp)
        }

        if mouseMoveMonitor == nil {
            logger.error("Failed to create the global mouse move event monitor.")
        } else {
            logger.info("Mouse move event monitor started.")
        }
    }

    private func stopMoveMonitoring() {
        guard let mouseMoveMonitor else { return }

        NSEvent.removeMonitor(mouseMoveMonitor)
        self.mouseMoveMonitor = nil
        logger.info("Mouse move event monitor stopped.")
    }

    // MARK: - Private Helpers

    /// Returns `true` if the event should be passed down the event chain, `false` to swallow it.
    @discardableResult
    fileprivate func handleClick(at location: CGPoint, with button: CGMouseButton) -> Bool {
        return clickHandler?(location, button) ?? true
    }

    private func handleMove(to location: CGPoint, timestamp: TimeInterval) {
        let minimumInterval = max(0, mouseUpdateDuration)
        guard
            lastMoveEventTimestamp == 0 || timestamp < lastMoveEventTimestamp
                || timestamp - lastMoveEventTimestamp >= minimumInterval
        else { return }

        lastMoveEventTimestamp = timestamp
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

// MARK: - C Callback for Input Events

private func inputEventMonitorCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon _: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if it was disabled by timeout or user input
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = InputEventMonitor.shared.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if type == .leftMouseDown {
        let location = event.location
        let passDown = InputEventMonitor.shared.handleClick(at: location, with: .left)
        if !passDown {
            return nil
        }
    } else if type == .rightMouseDown {
        let location = event.location
        let passDown = InputEventMonitor.shared.handleClick(at: location, with: .right)
        if !passDown {
            return nil
        }
    } else if type == .otherMouseDown {
        let location = event.location
        if let button = CGMouseButton(
            rawValue: UInt32(event.getIntegerValueField(.mouseEventButtonNumber)))
        {
            let passDown = InputEventMonitor.shared.handleClick(at: location, with: button)
            if !passDown {
                return nil
            }
        }
    } else if type == .keyDown {
        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let passDown = InputEventMonitor.shared.handleKey(flags: flags, keyCode: keyCode)
        if !passDown {
            return nil
        }
    }

    return Unmanaged.passRetained(event)
}
