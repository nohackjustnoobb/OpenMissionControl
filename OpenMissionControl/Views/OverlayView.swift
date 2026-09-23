//
//  OverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 14/3/2026.
//

import SwiftUI

enum OverlayTheme: String, CaseIterable, DisplayNameable {
    case classic
    case minimal
    case coloredMinimal
    case liquidGlass

    static var allCases: [OverlayTheme] {
        if #available(macOS 26.0, *) {
            return [.classic, .minimal, .coloredMinimal, .liquidGlass]
        }

        return [.classic, .minimal, .coloredMinimal]
    }

    var displayName: String {
        switch self {
        case .classic:
            return "Classic"
        case .minimal:
            return "Minimal"
        case .coloredMinimal:
            return "Colored Minimal"
        case .liquidGlass:
            return "Liquid Glass"
        }
    }
}

struct OverlayView: View {
    @AppStorage(SettingsDefaults.Key.overlayTheme) private var currentTheme: OverlayTheme =
        SettingsDefaults.overlayTheme
    @AppStorage(SettingsDefaults.Key.overlayButtonScale) private var overlayButtonScale: Double =
        SettingsDefaults.overlayButtonScale
    var isPreview: Bool = false

    var body: some View {
        let sizing = OverlaySizing(scale: overlayButtonScale)

        Group {
            switch currentTheme {
            case .classic:
                ClassicOverlayView(sizing: sizing)
            case .minimal:
                MinimalOverlayView(sizing: sizing)
            case .coloredMinimal:
                ColoredMinimalOverlayView(sizing: sizing)
            case .liquidGlass:
                if #available(macOS 26.0, *) {
                    LiquidGlassOverlayView(sizing: sizing)
                } else {
                    ClassicOverlayView(sizing: sizing)
                }
            }
        }
        .environment(\.isPreview, isPreview)
    }
}

private struct IsPreviewKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isPreview: Bool {
        get { self[IsPreviewKey.self] }
        set { self[IsPreviewKey.self] = newValue }
    }
}
