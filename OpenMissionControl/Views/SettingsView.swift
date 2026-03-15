//
//  SettingsView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 13/3/2026.
//

import SwiftUI

// MARK: - Reusable Setting Row

struct SettingToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(icon: String, iconColor: Color, title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [iconColor.opacity(0.85), iconColor], startPoint: .top, endPoint: .bottom))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Section Card

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 54)
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @AppStorage("showCloseButton") private var showCloseButton: Bool = true
    @AppStorage("showMinimizeButton") private var showMinimizeButton: Bool = true
    @AppStorage("showZoomButton") private var showZoomButton: Bool = true

    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                // MARK: General

                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("General")

                    SettingsCard {
                        SettingToggleRow(
                            icon: "arrow.trianglehead.2.clockwise",
                            iconColor: .blue,
                            title: "Launch at Login",
                            isOn: $launchAtLogin
                        )
                        .onChange(of: launchAtLogin) { enabled in
                            do {
                                if enabled {
                                    try LaunchAtLoginManager.enable()
                                } else {
                                    try LaunchAtLoginManager.disable()
                                }
                            } catch {
                                launchAtLogin = !enabled
                                print("Failed to update login item: \(error)")
                            }
                        }
                    }
                }

                // MARK: Overlay Buttons

                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Overlay")

                    SettingsCard {
                        SettingToggleRow(
                            icon: "xmark",
                            iconColor: .red,
                            title: "Close Button",
                            isOn: $showCloseButton
                        )

                        SettingsDivider()

                        SettingToggleRow(
                            icon: "minus",
                            iconColor: .yellow,
                            title: "Minimize Button",
                            isOn: $showMinimizeButton
                        )

                        SettingsDivider()

                        SettingToggleRow(
                            icon: "arrow.up.backward.and.arrow.down.forward",
                            iconColor: .green,
                            title: "Maximize Button",
                            isOn: $showZoomButton
                        )
                    }
                }

                // MARK: Preview

                if showCloseButton || showMinimizeButton || showZoomButton {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("Preview")

                        HStack(spacing: 0) {
                            Spacer()
                            trafficLightPreview
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private var trafficLightPreview: some View {
        HStack(spacing: 8) {
            if showCloseButton {
                trafficLight(color: .red, icon: "xmark")
            }
            if showMinimizeButton {
                trafficLight(color: .yellow, icon: "minus")
            }
            if showZoomButton {
                trafficLight(color: .green, icon: "arrow.up.backward.and.arrow.down.forward")
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
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    private func trafficLight(color: Color, icon: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
                .frame(width: 24, height: 24)
                .shadow(color: color.opacity(0.4), radius: 3, x: 0, y: 1)
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.black.opacity(0.45))
        }
    }
}
