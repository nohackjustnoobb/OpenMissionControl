//
//  MinimalOverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 21/3/2026.
//

import SwiftUI

struct MinimalOverlayView: View {
    let sizing: OverlaySizing

    @ObservedObject private var openMissionControlCore = OpenMissionControlCore.shared

    @AppStorage(SettingsDefaults.Key.showQuitButton) private var showQuitButton: Bool =
        SettingsDefaults.showQuitButton
    @AppStorage(SettingsDefaults.Key.showCloseButton) private var showCloseButton: Bool =
        SettingsDefaults.showCloseButton
    @AppStorage(SettingsDefaults.Key.showMinimizeButton) private var showMinimizeButton: Bool =
        SettingsDefaults.showMinimizeButton
    @AppStorage(SettingsDefaults.Key.showZoomButton) private var showZoomButton: Bool =
        SettingsDefaults.showZoomButton

    var body: some View {
        HStack(spacing: sizing.spacing) {
            if showQuitButton { overlayIcon(icon: "power", iconSize: 10) }

            if showCloseButton { overlayIcon(icon: "xmark", iconSize: 12) }

            if showMinimizeButton { overlayIcon(icon: "minus", iconSize: 15) }

            if showZoomButton {
                overlayIcon(icon: "arrow.up.backward.and.arrow.down.forward", iconSize: 12)
            }
        }
        .padding(.horizontal, sizing.horizontalPadding).padding(.vertical, sizing.verticalPadding)
        .background(Capsule().fill(Color(NSColor.windowBackgroundColor).opacity(0.95)))
        .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: sizing.borderWidth))
    }

    private func overlayIcon(icon: String, iconSize: CGFloat) -> some View {
        Image(systemName: icon).font(.system(size: iconSize * sizing.scale, weight: .bold))
            .foregroundColor(.primary).frame(width: sizing.buttonSize, height: sizing.buttonSize)
    }
}
