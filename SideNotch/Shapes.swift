import SwiftUI

/// The black bar that hangs off the right edge of the screen: straight on the
/// outer edge, rounded on the inner edge, and blended into the screen edge with
/// an inverse fillet at the top and bottom — the same trick the menu bar notch
/// uses so the shape looks grown out of the display rather than stuck onto it.
struct NotchShape: Shape {
    var cornerRadius: CGFloat = Layout.notchCornerRadius
    var filletRadius: CGFloat = Layout.filletRadius

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = filletRadius
        let R = min(cornerRadius, (h - 2 * r) / 2)

        var p = Path()
        p.move(to: CGPoint(x: w, y: 0))
        // Inverse fillet, screen edge → top of the body.
        p.addQuadCurve(to: CGPoint(x: w - r, y: r),
                       control: CGPoint(x: w - r, y: 0))
        // Top edge.
        p.addLine(to: CGPoint(x: R, y: r))
        p.addQuadCurve(to: CGPoint(x: 0, y: r + R),
                       control: CGPoint(x: 0, y: r))
        // Inner edge.
        p.addLine(to: CGPoint(x: 0, y: h - r - R))
        p.addQuadCurve(to: CGPoint(x: R, y: h - r),
                       control: CGPoint(x: 0, y: h - r))
        // Bottom edge.
        p.addLine(to: CGPoint(x: w - r, y: h - r))
        // Inverse fillet, bottom of the body → screen edge.
        p.addQuadCurve(to: CGPoint(x: w, y: h),
                       control: CGPoint(x: w - r, y: h))
        p.closeSubpath()
        return p
    }
}

/// A rounded card with a tail on its right edge pointing at the hovered ring.
struct CardShape: Shape {
    /// Tail centre, measured from the top of the shape.
    var tailCenterY: CGFloat
    var cornerRadius: CGFloat = Layout.cardCornerRadius
    var tailWidth: CGFloat = Layout.tailWidth
    var tailHeight: CGFloat = Layout.tailHeight

    var animatableData: CGFloat {
        get { tailCenterY }
        set { tailCenterY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width - tailWidth   // body width; the tail lives to its right
        let h = rect.height
        let R = cornerRadius
        let half = tailHeight / 2
        let center = min(max(tailCenterY, R + half), h - R - half)

        var p = Path()
        p.move(to: CGPoint(x: R, y: 0))
        p.addLine(to: CGPoint(x: w - R, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: R), control: CGPoint(x: w, y: 0))
        // Right edge, interrupted by the tail.
        p.addLine(to: CGPoint(x: w, y: center - half))
        p.addQuadCurve(to: CGPoint(x: w + tailWidth, y: center),
                       control: CGPoint(x: w + tailWidth * 0.55, y: center - half * 0.30))
        p.addQuadCurve(to: CGPoint(x: w, y: center + half),
                       control: CGPoint(x: w + tailWidth * 0.55, y: center + half * 0.30))
        p.addLine(to: CGPoint(x: w, y: h - R))
        p.addQuadCurve(to: CGPoint(x: w - R, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: R, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - R), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: R))
        p.addQuadCurve(to: CGPoint(x: R, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}
