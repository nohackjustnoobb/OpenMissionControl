//
//  ColoredMinimalOverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 25/3/2026.
//

import SwiftUI

struct ColoredMinimalOverlayView: View {
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
            if showQuitButton { overlayIcon(color: .purple, icon: .system("power"), iconSize: 11) }

            if showCloseButton { overlayIcon(color: .red, icon: .system("xmark"), iconSize: 13) }

            if showMinimizeButton {
                overlayIcon(color: .yellow, icon: .system("minus"), iconSize: 13)
            }

            if showZoomButton { overlayIcon(color: .green, icon: .fullscreen, iconSize: 12) }
        }
        .padding(.horizontal, sizing.horizontalPadding).padding(.vertical, sizing.verticalPadding)
        .background(Capsule().fill(Color(NSColor.windowBackgroundColor).opacity(0.95)))
        .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: sizing.borderWidth))
    }

    private func overlayIcon(color: Color, icon: OverlayIcon, iconSize: CGFloat) -> some View {
        icon.view(size: iconSize * sizing.scale).foregroundColor(color)
            .frame(width: sizing.buttonSize, height: sizing.buttonSize)
    }
}
