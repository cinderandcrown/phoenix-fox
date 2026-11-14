// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

/// The Phoenix Fox mark, drawn from `FoxMarkGeometry`. The app icon is the same drawing.
struct FoxMark: View {
    var body: some View {
        ZStack {
            FoxOutline(outlines: [FoxMarkGeometry.head])
                .fill(LinearGradient(colors: [Theme.garnet, Theme.ember, Theme.flame, Theme.gold], startPoint: .top, endPoint: .bottom))
            FoxOutline(outlines: [FoxMarkGeometry.blaze])
                .fill(LinearGradient(colors: [Theme.gold, Color(BrandPalette.ink.dark)], startPoint: .top, endPoint: .bottom))
            FoxOutline(outlines: FoxMarkGeometry.eyes)
                .fill(Theme.onFire)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Outlines from the unit square, scaled to fit the space given.
struct FoxOutline: Shape {
    let outlines: [FoxMarkGeometry.Outline]

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func place(_ point: FoxMarkGeometry.Point) -> CGPoint {
            CGPoint(x: origin.x + point.x * side, y: origin.y + point.y * side)
        }
        var path = Path()
        for outline in outlines {
            path.move(to: place(outline.start))
            for curve in outline.curves {
                path.addCurve(to: place(curve.end), control1: place(curve.control1), control2: place(curve.control2))
            }
            path.closeSubpath()
        }
        return path
    }
}

#Preview("Mark") {
    FoxMark()
        .frame(width: 160, height: 160)
        .padding(40)
        .background(Theme.canvas)
}
