//
//  OverlayView.swift
//  OpenMissionControl
//
//  Created by Travis XU on 14/3/2026.
//

import SwiftUI

enum OverlayTheme: String, CaseIterable {
    case `default`
    case minimal
    case coloredMinimal

    var displayName: String {
        switch self {
        case .default:
            return "Default"
        case .minimal:
            return "Minimal"
        case .coloredMinimal:
            return "Colored Minimal"
        }
    }
}

struct OverlayView: View {
    @AppStorage("overlayTheme") private var currentTheme: OverlayTheme = .default
    var isPreview: Bool = false

    var body: some View {
        Group {
            switch currentTheme {
            case .default:
                DefaultOverlayView()
            case .minimal:
                MinimalOverlayView()
            case .coloredMinimal:
                ColoredMinimalOverlayView()
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
