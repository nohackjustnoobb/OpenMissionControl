//
//  ClassicOverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 21/3/2026.
//

import SwiftUI

struct ClassicOverlayView: View {
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
        .background(Capsule().fill(Color(NSColor.windowBackgroundColor).opacity(0.95)))
        .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: sizing.borderWidth))
    }

    private func trafficLight(color: Color, icon: String, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: sizing.buttonSize, height: sizing.buttonSize)
                .shadow(
                    color: color.opacity(0.4), radius: sizing.shadowRadius, x: 0,
                    y: sizing.shadowYOffset)
            Image(systemName: icon).font(.system(size: iconSize * sizing.scale, weight: .bold))
                .foregroundColor(
                    (openMissionControlCore.isOverlayHovered || isPreview)
                        ? Color.black.opacity(0.45) : .clear)
        }
    }
}
