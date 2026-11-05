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

/// Monitors global input events and notifies registered handlers on mouse release, move, and key events.
class InputEventMonitor {
    static let shared = InputEventMonitor()

    // MARK: - Types

    typealias ClickHandler = (_ location: CGPoint, _ buttonCode: CGMouseButton, _ wasConsumed: Bool)
        -> Void
    typealias MouseDownHandler = (_ location: CGPoint, _ buttonCode: CGMouseButton) -> Bool
    typealias MoveHandler = (_ location: CGPoint) -> Void
    typealias KeyHandler = (_ flags: CGEventFlags, _ keyCode: CGKeyCode) -> Bool

    // MARK: - Properties

    @AppStorage(SettingsDefaults.Key.mouseUpdateDuration) private var mouseUpdateDuration: Double =
        SettingsDefaults.mouseUpdateDuration

    private let logger = Logger(
        subsystem: "dev.travisxu.OpenMissionControl", category: "InputEventMonitor")

    private var clickHandler: ClickHandler?
    private var mouseDownHandler: MouseDownHandler?
    private var moveHandler: MoveHandler?
    private var keyHandler: KeyHandler?
    private(set) var isMonitoring: Bool = false

    // MARK: - Input Monitoring (CGEvent tap)

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var consumedMouseButtons: Set<CGMouseButton> = []

    // MARK: - Move Monitoring (NSEvent)

    private var mouseMoveMonitor: Any?
    private var lastMoveEventTimestamp: TimeInterval = 0

    // MARK: - Public Interface

    func setClickHandler(_ handler: @escaping ClickHandler) { clickHandler = handler }

    func setMouseDownHandler(_ handler: @escaping MouseDownHandler) { mouseDownHandler = handler }

    func setMoveHandler(_ handler: @escaping MoveHandler) { moveHandler = handler }

    func setKeyHandler(_ handler: @escaping KeyHandler) { keyHandler = handler }

    func start() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastMoveEventTimestamp = 0

        if eventTap == nil { startInputMonitoring() }
        startMoveMonitoring()

        logger.info("Input event monitoring started.")
    }

    func stop() {
        guard isMonitoring else { return }

        isMonitoring = false
        stopMoveMonitoring()
        // Keep the tap alive until it has consumed the releases for any captured presses.
        if consumedMouseButtons.isEmpty { stopInputMonitoring() }
        lastMoveEventTimestamp = 0

        logger.info("Input event monitoring stopped.")
    }

    // MARK: - Private: Input Monitoring

    private func startInputMonitoring() {
        let eventMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: eventMask, callback: inputEventMonitorCallback, userInfo: nil)
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
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)

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

    // Mouse event handlers return true when the event should be consumed.
    fileprivate func handleMouseDown(at location: CGPoint, with button: CGMouseButton) -> Bool {
        if isMonitoring, mouseDownHandler?(location, button) == true {
            consumedMouseButtons.insert(button)
        }
        return consumedMouseButtons.contains(button)
    }

    fileprivate func handleMouseUp(at location: CGPoint, with button: CGMouseButton) -> Bool {
        let wasConsumed = consumedMouseButtons.remove(button) != nil
        if isMonitoring {
            clickHandler?(location, button, wasConsumed)
        } else if wasConsumed, consumedMouseButtons.isEmpty {
            // Let the callback discard this release before disabling the tap.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isMonitoring, self.consumedMouseButtons.isEmpty else {
                    return
                }
                self.stopInputMonitoring()
            }
        }
        return wasConsumed
    }

    fileprivate func shouldConsumeMouseDrag(for button: CGMouseButton) -> Bool {
        consumedMouseButtons.contains(button)
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

    @discardableResult fileprivate func handleKey(flags: CGEventFlags, keyCode: CGKeyCode) -> Bool {
        guard isMonitoring else { return true }
        return keyHandler?(flags, keyCode) ?? true
    }

    // MARK: - Lifecycle

    deinit { stop() }
}

// MARK: - C Callback for Input Events

private func inputEventMonitorCallback(
    proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon _: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let monitor = InputEventMonitor.shared

    // Re-enable tap if it was disabled by timeout or user input
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if !monitor.handleKey(flags: flags, keyCode: keyCode) { return nil }
        return Unmanaged.passUnretained(event)
    }

    let mouseButton: CGMouseButton?
    switch type { case .leftMouseDown, .leftMouseUp, .leftMouseDragged: mouseButton = .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: mouseButton = .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            mouseButton = CGMouseButton(
                rawValue: UInt32(event.getIntegerValueField(.mouseEventButtonNumber)))
        default: mouseButton = nil
    }
    guard let button = mouseButton else { return Unmanaged.passUnretained(event) }

    let wasConsumed: Bool
    switch type { case .leftMouseDown, .rightMouseDown, .otherMouseDown:
        wasConsumed = monitor.handleMouseDown(at: event.location, with: button)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            wasConsumed = monitor.handleMouseUp(at: event.location, with: button)
        default: wasConsumed = monitor.shouldConsumeMouseDrag(for: button)
    }
    return wasConsumed ? nil : Unmanaged.passUnretained(event)
}
