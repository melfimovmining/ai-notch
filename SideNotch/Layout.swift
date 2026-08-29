import CoreGraphics

/// Every hard number the panel geometry depends on, in points.
///
/// The panel is laid out like this (seen from the front):
///
///     ┌──────────────────────────── panel ────────────────────────────┐
///     │  shadowPad │      card + tail      │ gap │   notch   │        │
///     └───────────────────────────────────────────────────────────────┘
///                                                            ▲ screen edge
enum Layout {
    // Notch bar
    static let notchWidth: CGFloat = 120
    /// Radius of the two convex corners on the notch's inner (left) side.
    static let notchCornerRadius: CGFloat = 34
    /// Radius of the inverse fillets that blend the bar into the screen edge.
    static let filletRadius: CGFloat = 22
    static let notchVerticalPadding: CGFloat = 30

    // Rings
    static let ringDiameter: CGFloat = 66
    static let ringLineWidth: CGFloat = 5.5
    static let ringIconSize: CGFloat = 26
    static let percentFontSize: CGFloat = 19
    static let percentTopGap: CGFloat = 6
    static let ringSpacing: CGFloat = 42

    /// Ring + gap + percentage label.
    static var itemHeight: CGFloat { ringDiameter + percentTopGap + percentFontSize + 4 }
    /// Distance between the centres of two consecutive rings.
    static var itemStride: CGFloat { itemHeight + ringSpacing }

    /// How many rings the geometry is currently sized for. Set once at launch
    /// from the number of metrics on screen; the spend ring is optional, so
    /// this is not a constant.
    static var ringCount: Int = 3

    /// Height of the black bar's straight body.
    static func notchBodyHeight(rings: Int) -> CGFloat {
        let rings = max(rings, 1)
        return notchVerticalPadding * 2 + itemHeight * CGFloat(rings)
            + ringSpacing * CGFloat(rings - 1)
    }

    static var notchBodyHeight: CGFloat { notchBodyHeight(rings: ringCount) }

    /// Total height of the notch shape, including the fillet overhang.
    static var notchShapeHeight: CGFloat { notchBodyHeight + filletRadius * 2 }

    // Hover card
    static let cardWidth: CGFloat = 300
    /// Fixed so the tail can be centred without measuring the card.
    static let cardHeight: CGFloat = 176
    static let cardCornerRadius: CGFloat = 22
    static let tailWidth: CGFloat = 14
    static let tailHeight: CGFloat = 34
    /// Space between the tail's tip and the notch's left edge.
    static let cardGap: CGFloat = 2

    // Collapsed tab — the "peek" the notch hides behind.
    static let tabWidth: CGFloat = 12
    static let tabHoverWidth: CGFloat = 18
    static let tabHeight: CGFloat = 72
    static let tabCornerRadius: CGFloat = 6
    static let tabFilletRadius: CGFloat = 4

    // Panel
    /// Slack around the content so shadows are not clipped by the window.
    static let shadowPad: CGFloat = 40

    static var panelWidth: CGFloat {
        shadowPad + cardWidth + tailWidth + cardGap + notchWidth
    }
    static var panelHeight: CGFloat { notchShapeHeight + shadowPad * 2 }

    /// The notch's frame inside the panel, in SwiftUI (top-left origin) coordinates.
    static var notchFrameInPanel: CGRect {
        CGRect(x: panelWidth - notchWidth,
               y: shadowPad,
               width: notchWidth,
               height: notchShapeHeight)
    }

    /// Vertical centre shared by the expanded bar and the collapsed tab, so the
    /// one grows out of the other without drifting.
    static var contentCenterY: CGFloat { shadowPad + notchShapeHeight / 2 }

    /// Frame of the collapsed tab, in SwiftUI panel coordinates.
    static func tabFrameInPanel(width: CGFloat = tabWidth) -> CGRect {
        CGRect(x: panelWidth - width,
               y: contentCenterY - tabHeight / 2,
               width: width,
               height: tabHeight)
    }

    /// The only part of the panel that should claim mouse events, given the
    /// current state. Everything else stays click-through.
    static func interactiveFrameInPanel(expanded: Bool) -> CGRect {
        expanded ? notchFrameInPanel : tabFrameInPanel(width: tabHoverWidth)
    }

    /// Centre of ring `index`, in SwiftUI panel coordinates.
    static func ringCenterY(_ index: Int) -> CGFloat {
        shadowPad + filletRadius + notchVerticalPadding
            + CGFloat(index) * itemStride + ringDiameter / 2
    }
}
