//
//  DefaultOverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 21/3/2026.
//

import SwiftUI

struct DefaultOverlayView: View {
    @Environment(\.isPreview) private var isPreview
    @ObservedObject private var openMissionControlCore = OpenMissionControlCore.shared

    @AppStorage("showCloseButton") private var showCloseButton: Bool = true
    @AppStorage("showMinimizeButton") private var showMinimizeButton: Bool = true
    @AppStorage("showZoomButton") private var showZoomButton: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            if showCloseButton {
                trafficLight(color: .red, icon: "xmark", iconSize: 10)
            }
            if showMinimizeButton {
                trafficLight(color: .yellow, icon: "minus", iconSize: 12)
            }
            if showZoomButton {
                trafficLight(color: .green, icon: "arrow.up.backward.and.arrow.down.forward", iconSize: 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func trafficLight(color: Color, icon: String, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [color.opacity(0.85), color],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 24, height: 24)
                .shadow(color: color.opacity(0.4), radius: 3, x: 0, y: 1)
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor((openMissionControlCore.isOverlayHovered || isPreview) ? Color.black.opacity(0.45) : .clear)
        }
    }
}
