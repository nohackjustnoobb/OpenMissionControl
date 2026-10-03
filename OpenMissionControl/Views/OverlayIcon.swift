//
//  OverlayIcon.swift
//  OpenMissionControl
//
//  Created by Travis XU on 3/10/2026.
//

import SwiftUI

enum OverlayIcon {
    case system(String)
    case fullscreen

    @ViewBuilder func view(size: CGFloat, weight: Font.Weight = .bold) -> some View {
        switch self { case .system(let name):
            Image(systemName: name).font(.system(size: size, weight: weight))
            case .fullscreen: FullscreenGlyph().frame(width: size, height: size)
        }
    }
}

// The macOS green button uses two filled triangles pointing outwards.
private struct FullscreenGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.85, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.85))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
