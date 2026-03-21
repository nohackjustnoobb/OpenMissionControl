//
//  SettingsView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 13/3/2026.
//

import ApplicationServices
import Combine
import OSLog
import SwiftUI

// MARK: - Accessibility Row

struct AccessibilityRow: View {
    @State private var isTrusted: Bool = AXIsProcessTrusted()
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.85), Color.blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 28, height: 28)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility")
                    .font(.system(size: 13, weight: .medium))
                Text(isTrusted ? "Granted" : "Required for window actions")
                    .font(.system(size: 11))
                    .foregroundStyle(isTrusted ? Color.secondary : Color.red)
            }

            Spacer()

            if !isTrusted {
                Button("Grant") {
                    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    let accessEnabled = AXIsProcessTrustedWithOptions(options)
                    isTrusted = accessEnabled
                    if !accessEnabled {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onReceive(timer) { _ in
            let trusted = AXIsProcessTrusted()
            if isTrusted != trusted {
                isTrusted = trusted
            }
        }
    }
}

// MARK: - Reusable Setting Row

struct SettingToggleRow: View {
    let icon: String?
    let iconColor: Color
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(icon: String? = nil, iconColor: Color = .blue, title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [iconColor.opacity(0.85), iconColor], startPoint: .top, endPoint: .bottom))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
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
    @AppStorage("overlayTheme") private var currentTheme: OverlayTheme = .default

    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    private let logger = Logger(subsystem: "dev.travisxu.OpenMissionControl", category: "SettingsView")

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // MARK: Permissions

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Permissions")

                SettingsCard {
                    AccessibilityRow()
                }
            }

            // MARK: General

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("General")

                SettingsCard {
                    SettingToggleRow(
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
                            logger.error("Failed to update login item: \(error)")
                        }
                    }
                }
            }

            // MARK: Overlay Buttons

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Overlay")

                SettingsCard {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(colors: [Color.purple.opacity(0.85), Color.purple], startPoint: .top, endPoint: .bottom))
                                .frame(width: 28, height: 28)
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Theme")
                                .font(.system(size: 13, weight: .medium))
                        }

                        Spacer()

                        Picker("", selection: $currentTheme) {
                            ForEach(OverlayTheme.allCases, id: \.self) { theme in
                                Text(theme.rawValue.capitalized).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    SettingsDivider()

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
                        OverlayView(isPreview: true)
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

            // MARK: About

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("About")

                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Open Mission Control")
                                .font(.system(size: 13, weight: .medium))
                            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                                Text("Version \(version) (\(build))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Link(destination: URL(string: "https://github.com/nohackjustnoobb/OpenMissionControl")!) {
                            HStack(spacing: 4) {
                                Text("GitHub")
                                Image(systemName: "link")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}
