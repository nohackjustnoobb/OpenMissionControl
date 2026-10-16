//
//  OverlayWindowPositioner.swift
//  OpenMissionControl
//
//  Created by Travis XU on 16/10/2026.
//

import AppKit
import CoreGraphics
import Darwin

@_silgen_name("CGSMainConnectionID") private func overlayWindowConnectionID() -> UInt32

enum OverlayWindowPositioner {
    private typealias SetWindowTransform =
        @convention(c) (UInt32, CGWindowID, CGAffineTransform) -> CGError

    private static let skyLightHandle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    private static let setWindowTransform: SetWindowTransform? = {
        guard let skyLightHandle, let symbol = dlsym(skyLightHandle, "SLSSetWindowTransform") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetWindowTransform.self)
    }()

    private static var usesWindowTransforms: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            && setWindowTransform != nil
    }

    static var initialWindowSize: CGSize {
        guard usesWindowTransforms else { return CGSize(width: 1, height: 1) }

        let sizing = OverlaySizing(scale: OverlaySizing.scaleRange.upperBound)
        return CGSize(
            width: sizing.width(buttonCount: 4) + 2 * sizing.margin,
            height: sizing.height + 2 * sizing.margin)
    }

    static func setFrame(_ frame: NSRect, for window: NSWindow, cgOrigin: CGPoint) -> NSRect {
        if usesWindowTransforms, let setWindowTransform, window.windowNumber > 0 {
            // Mission Control animates native moves and resizes on macOS 27 regardless of AppKit's animation flags.
            // Leave the compact backing window fixed and move only its presentation.
            // WindowServer maps screen coordinates back into the window buffer, so use the inverse of the desired top-left position.
            let transform = CGAffineTransform(translationX: -cgOrigin.x, y: -cgOrigin.y)
            let result = setWindowTransform(
                overlayWindowConnectionID(), CGWindowID(window.windowNumber), transform)
            if result == .success {
                // Align the controls to the top-left of the fixed backing surface.
                return NSRect(
                    x: 0, y: window.frame.height - frame.height, width: frame.width,
                    height: frame.height)
            }
        }

        window.setFrame(frame, display: false, animate: false)
        return window.contentView?.bounds ?? .zero
    }
}
