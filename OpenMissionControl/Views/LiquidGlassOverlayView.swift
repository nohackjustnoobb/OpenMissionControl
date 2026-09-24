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
            if showQuitButton { trafficLight(color: .purple, icon: "power", iconSize: 10) }

            if showCloseButton { trafficLight(color: .red, icon: "xmark", iconSize: 10) }

            if showMinimizeButton { trafficLight(color: .yellow, icon: "minus", iconSize: 12) }

            if showZoomButton {
                trafficLight(
                    color: .green, icon: "arrow.up.backward.and.arrow.down.forward", iconSize: 10)
            }
        }
        .padding(.horizontal, sizing.horizontalPadding).padding(.vertical, sizing.verticalPadding)
        .glassEffect(.regular, in: Capsule())
    }

    private func trafficLight(color: Color, icon: String, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.88), color.opacity(0.70)], startPoint: .topLeading,
                        endPoint: .bottomTrailing)
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(0.28), lineWidth: sizing.borderWidth)
                }
                .frame(width: sizing.buttonSize, height: sizing.buttonSize)
                .shadow(
                    color: color.opacity(0.18), radius: 2 * sizing.scale, x: 0,
                    y: sizing.shadowYOffset)

            Image(systemName: icon).font(.system(size: iconSize * sizing.scale, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.45))
                .opacity((openMissionControlCore.isOverlayHovered || isPreview) ? 1 : 0)
        }
    }
}
