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
