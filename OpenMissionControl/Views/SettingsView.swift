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

// MARK: - Icon color gradient builders

private func solidColor(color: Color) -> LinearGradient {
    return LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)
}

private let rainbowColor = LinearGradient(
    colors: [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple],
    startPoint: .top, endPoint: .bottom)

// MARK: - Accessibility Row

struct AccessibilityRow: View {
    @State private var isTrusted: Bool = AXIsProcessTrusted()
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.85), Color.blue], startPoint: .top,
                            endPoint: .bottom)
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: "hand.raised.fill").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility").font(.system(size: 13, weight: .medium))
                Text(isTrusted ? "Granted" : "Required for window actions").font(.system(size: 11))
                    .foregroundStyle(isTrusted ? Color.secondary : Color.red)
            }

            Spacer()

            if !isTrusted {
                Button("Grant") {
                    let options: NSDictionary = [
                        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                    ]
                    let accessEnabled = AXIsProcessTrustedWithOptions(options)
                    isTrusted = accessEnabled
                }
                .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .onReceive(timer) { _ in
            let trusted = AXIsProcessTrusted()
            if isTrusted != trusted { isTrusted = trusted }
        }
    }
}

// MARK: - Reusable Setting Row

struct SettingToggleRow: View {
    let icon: String?
    let iconColor: LinearGradient
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(
        icon: String? = nil, iconColor: LinearGradient? = nil, title: String,
        subtitle: String? = nil, isOn: Binding<Bool>
    ) {
        self.icon = icon
        self.iconColor = iconColor ?? solidColor(color: .blue)
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(iconColor)
                        .frame(width: 28, height: 28)
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

struct SettingPickerRow<Value>: View where Value: Hashable & CaseIterable & DisplayNameable {
    let icon: String?
    let iconColor: LinearGradient
    let title: String
    @Binding var selectedValue: Value

    init(
        icon: String? = nil, iconColor: LinearGradient? = nil, title: String,
        selectedValue: Binding<Value>
    ) {
        self.icon = icon
        self.iconColor = iconColor ?? solidColor(color: .blue)
        self.title = title
        _selectedValue = selectedValue
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(iconColor)
                        .frame(width: 28, height: 28)
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
            }

            Spacer()

            Picker("", selection: $selectedValue) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .labelsHidden().frame(width: 100)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

// MARK: - Section Card

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct SettingsDivider: View { var body: some View { Divider().padding(.leading, 54) } }

private enum SettingsTab: Hashable {
    case general
    case overlay
    case shortcuts
    case about
}

// MARK: - Main Settings View

struct SettingsView: View {
    @AppStorage(SettingsDefaults.Key.showMenuBarIcon) private var showMenuBarIcon: Bool =
        SettingsDefaults.showMenuBarIcon
    @AppStorage(SettingsDefaults.Key.showQuitButton) private var showQuitButton: Bool =
        SettingsDefaults.showQuitButton
    @AppStorage(SettingsDefaults.Key.showCloseButton) private var showCloseButton: Bool =
        SettingsDefaults.showCloseButton
    @AppStorage(SettingsDefaults.Key.showMinimizeButton) private var showMinimizeButton: Bool =
        SettingsDefaults.showMinimizeButton
    @AppStorage(SettingsDefaults.Key.showZoomButton) private var showZoomButton: Bool =
        SettingsDefaults.showZoomButton
    @AppStorage(SettingsDefaults.Key.overlayTheme) private var currentTheme: OverlayTheme =
        SettingsDefaults.overlayTheme
    @AppStorage(SettingsDefaults.Key.overlayButtonScale) private var overlayButtonScale: Double =
        SettingsDefaults.overlayButtonScale
    @AppStorage(SettingsDefaults.Key.updateDuration) private var updateDuration: Double =
        SettingsDefaults.updateDuration
    @AppStorage(SettingsDefaults.Key.mouseUpdateDuration) private var mouseUpdateDuration: Double =
        SettingsDefaults.mouseUpdateDuration
    @AppStorage(SettingsDefaults.Key.shortcutQuit) private var shortcutQuit: Bool = SettingsDefaults
        .shortcutQuit
    @AppStorage(SettingsDefaults.Key.shortcutClose) private var shortcutClose: Bool =
        SettingsDefaults.shortcutClose
    @AppStorage(SettingsDefaults.Key.shortcutMinimize) private var shortcutMinimize: Bool =
        SettingsDefaults.shortcutMinimize
    @AppStorage(SettingsDefaults.Key.shortcutMaximize) private var shortcutMaximize: Bool =
        SettingsDefaults.shortcutMaximize
    @AppStorage(SettingsDefaults.Key.shortcutActivateWindow) private var shortcutActivateWindow:
        Bool = SettingsDefaults.shortcutActivateWindow
    @AppStorage(SettingsDefaults.Key.rightClickAction) private var rightClickAction: WindowAction =
        SettingsDefaults.rightClickAction
    @AppStorage(SettingsDefaults.Key.middleClickAction) private var middleClickAction:
        WindowAction = SettingsDefaults.middleClickAction

    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    @State private var selectedTab: SettingsTab = .general
    private let logger = Logger(
        subsystem: "dev.travisxu.OpenMissionControl", category: "SettingsView")

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            overlayTab.tabItem { Label("Overlay", systemImage: "rectangle.on.rectangle") }
                .tag(SettingsTab.overlay)

            shortcutTab.tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            aboutTab.tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(minWidth: 520, minHeight: 600).tabViewStyle(.automatic)
    }

    private var generalTab: some View {
        settingsScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Permissions")
                    SettingsCard { AccessibilityRow() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("General")
                    SettingsCard {
                        SettingToggleRow(
                            icon: "menubar.rectangle", title: "Show Menu Bar Icon",
                            subtitle: "Keep quick access to Settings and Quit.",
                            isOn: $showMenuBarIcon)

                        SettingsDivider()

                        SettingToggleRow(title: "Launch at Login", isOn: $launchAtLogin)
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

                        SettingsDivider()
                        durationRow(
                            title: "Window Update Duration", value: $updateDuration,
                            range: 0.05...2.0, help: "The interval for polling window state.")

                        SettingsDivider()
                        durationRow(
                            title: "Mouse Update Duration", value: $mouseUpdateDuration,
                            range: 0.05...1.0, help: "The interval for polling mouse state.")
                    }
                }
            }
        }
    }

    private var overlayTab: some View {
        settingsScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Overlay")
                    SettingsCard {
                        SettingPickerRow<OverlayTheme>(
                            icon: "paintpalette.fill", iconColor: rainbowColor, title: "Theme",
                            selectedValue: $currentTheme)

                        SettingsDivider()
                        overlaySizeRow
                        SettingsDivider()

                        SettingToggleRow(
                            icon: "power", iconColor: solidColor(color: .purple),
                            title: "Quit Button", isOn: $showQuitButton)

                        SettingsDivider()
                        SettingToggleRow(
                            icon: "xmark", iconColor: solidColor(color: .red),
                            title: "Close Button", isOn: $showCloseButton)

                        SettingsDivider()
                        SettingToggleRow(
                            icon: "minus", iconColor: solidColor(color: .yellow),
                            title: "Minimize Button", isOn: $showMinimizeButton)

                        SettingsDivider()
                        SettingToggleRow(
                            icon: "arrow.up.backward.and.arrow.down.forward",
                            iconColor: solidColor(color: .green), title: "Maximize Button",
                            isOn: $showZoomButton)
                    }
                }

                if showQuitButton || showCloseButton || showMinimizeButton || showZoomButton {
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
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
            }
        }
    }

    private var shortcutTab: some View {
        settingsScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Keyboard Shortcuts")
                    SettingsCard {
                        SettingToggleRow(
                            title: "Activate Window (Return/Enter)", isOn: $shortcutActivateWindow)
                        SettingsDivider()
                        SettingToggleRow(title: "Quit (⌘Q)", isOn: $shortcutQuit)
                        SettingsDivider()
                        SettingToggleRow(title: "Close (⌘W)", isOn: $shortcutClose)
                        SettingsDivider()
                        SettingToggleRow(title: "Minimize (⌘M)", isOn: $shortcutMinimize)
                        SettingsDivider()
                        SettingToggleRow(title: "Maximize (⌘F)", isOn: $shortcutMaximize)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("Mouse Shortcuts")
                    SettingsCard {
                        SettingPickerRow<WindowAction>(
                            title: "Right-click action", selectedValue: $rightClickAction)
                        SettingsDivider()
                        SettingPickerRow<WindowAction>(
                            title: "Middle-click action", selectedValue: $middleClickAction)
                    }
                }
            }
        }
    }

    private var aboutTab: some View {
        settingsScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("About")
                    SettingsCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
                                        ?? "Open Mission Control"
                                )
                                .font(.system(size: 13, weight: .medium))

                                if let version = Bundle.main.infoDictionary?[
                                    "CFBundleShortVersionString"] as? String,
                                    let build = Bundle.main.infoDictionary?["CFBundleVersion"]
                                        as? String
                                {
                                    Text("Version \(version) (\(build))").font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Link(
                                destination: URL(
                                    string: "https://github.com/nohackjustnoobb/OpenMissionControl")!
                            ) {
                                HStack(spacing: 4) {
                                    Text("GitHub")
                                    Image(systemName: "link")
                                }
                            }
                            .font(.system(size: 12)).foregroundColor(.blue)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
            }
        }
    }

    @ViewBuilder private func settingsScrollView<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { geometry in
            ScrollView {
                content().padding(16).frame(width: geometry.size.width, alignment: .leading)
            }
        }
    }

    private func durationRow(
        title: String, value: Binding<Double>, range: ClosedRange<Double>, help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: "%.2f s", value.wrappedValue)).font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.05).controlSize(.small)
            Text(help).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var overlaySizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Overlay Size").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%%", overlayButtonScale * 100)).font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $overlayButtonScale, in: OverlaySizing.scaleRange,
                step: OverlaySizing.scaleStep
            )
            .controlSize(.small)
            Text("The size of the Mission Control overlay.").font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary).padding(.leading, 4)
    }
}
