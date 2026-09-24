//
//  OverlaySizing.swift
//  OpenMissionControl
//
//  Created by Ckyac on 10/8/2026.
//

import Foundation

struct OverlaySizing {
    static let scaleRange: ClosedRange<Double> = 0.5...1.5
    static let scaleStep: Double = 0.05

    let scale: CGFloat

    init(scale: Double) { self.scale = CGFloat(scale) }

    var buttonSize: CGFloat { 24 * scale }
    var spacing: CGFloat { 8 * scale }
    var horizontalPadding: CGFloat { 10 * scale }
    var verticalPadding: CGFloat { 8 * scale }
    var borderWidth: CGFloat { 0.5 * scale }
    var shadowRadius: CGFloat { 3 * scale }
    var shadowYOffset: CGFloat { scale }
    var buttonStride: CGFloat { buttonSize + spacing }
    var height: CGFloat { buttonSize + 2 * verticalPadding }

    func width(buttonCount: Int) -> CGFloat {
        2 * horizontalPadding + CGFloat(buttonCount) * buttonSize + CGFloat(max(0, buttonCount - 1))
            * spacing
    }
}
