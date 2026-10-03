//
//  LiquidGlassOverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 23/9/2026.
//

import SwiftUI

@available(macOS 26.0, *) struct LiquidGlassOverlayView: View {
    let sizing: OverlaySizing

    @Environment(\.isPreview) private var isPreview
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
            if showQuitButton { trafficLight(color: .purple, icon: .system("power"), iconSize: 11) }

            if showCloseButton { trafficLight(color: .red, icon: .system("xmark"), iconSize: 11) }

            if showMinimizeButton {
                trafficLight(color: .yellow, icon: .system("minus"), iconSize: 12)
            }

            if showZoomButton { trafficLight(color: .green, icon: .fullscreen, iconSize: 10) }
        }
        .padding(.horizontal, sizing.horizontalPadding).padding(.vertical, sizing.verticalPadding)
        .glassEffect(.regular, in: Capsule())
    }

    private func trafficLight(color: Color, icon: OverlayIcon, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.85), color.opacity(0.5)], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .overlay {
                    Circle().stroke(Color.black.opacity(0.1), lineWidth: sizing.borderWidth)
                }
                .frame(width: sizing.buttonSize, height: sizing.buttonSize)
                .shadow(
                    color: color.opacity(0.2), radius: 2 * sizing.scale, x: 0,
                    y: sizing.shadowYOffset)

            icon.view(size: iconSize * sizing.scale).foregroundStyle(Color.black.opacity(0.4))
                .opacity((openMissionControlCore.isOverlayHovered || isPreview) ? 1 : 0)
        }
    }
}
