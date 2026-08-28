import SwiftUI
import AppKit

/// Draws the app icon and writes a full `.iconset`. Every size is rendered from
/// the vector artwork rather than downscaled from one big PNG, so the 16pt icon
/// stays crisp. Not part of the app target.
///
///     swiftc -parse-as-library ... tools/MakeIcon.swift SideNotch/Shapes.swift SideNotch/Layout.swift
///     ./build/makeicon /path/to/AppIcon.iconset
struct IconView: View {
    /// Canvas edge, in points.
    let size: CGFloat

    private var tileInset: CGFloat { size * 0.088 }
    private var tileSize: CGFloat { size - tileInset * 2 }
    private var cornerRadius: CGFloat { size * 0.186 }

    /// Below ~40px the full composition turns to mush, so the small sizes get
    /// simplified artwork: no bar, no glyph, one big ring. Same trick Apple's
    /// own icons use.
    private var compact: Bool { size <= 40 }

    private var barWidth: CGFloat { tileSize * 0.20 }
    private var barHeight: CGFloat { tileSize * 0.66 }

    private var ringDiameter: CGFloat { compact ? tileSize * 0.74 : tileSize * 0.46 }
    private var ringLineWidth: CGFloat { compact ? tileSize * 0.16 : tileSize * 0.082 }

    /// Centred in the tile when compact, otherwise in the space left of the bar.
    private var ringCenterX: CGFloat {
        compact ? size / 2 : tileInset + (tileSize - barWidth) / 2
    }

    var body: some View {
        ZStack {
            tile
            ring
        }
        .frame(width: size, height: size)
    }

    /// Gradient ground + the bar, clipped to the icon silhouette so the bar
    /// reads as part of the tile rather than a slab stuck on top of it.
    private var tile: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.20, blue: 0.22),
                                    Color(red: 0.06, green: 0.06, blue: 0.07)],
                           startPoint: .top, endPoint: .bottom)

            if !compact {
                NotchShape(cornerRadius: barWidth * 0.42, filletRadius: barWidth * 0.20)
                    .fill(Color.black)
                    .frame(width: barWidth, height: barHeight)
                    .shadow(color: .black.opacity(0.6), radius: tileSize * 0.03, x: -tileSize * 0.008)
                    .position(x: tileSize - barWidth / 2, y: tileSize / 2)
            }
        }
        .frame(width: tileSize, height: tileSize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            // A hairline of light along the top edge, the way glass catches it.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: max(1, size * 0.005)
                )
                .frame(width: tileSize, height: tileSize)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), style: .init(lineWidth: ringLineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: 0.73)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1.00, green: 0.38, blue: 0.16),
                            Color(red: 0.99, green: 0.75, blue: 0.18),
                            Color(red: 0.20, green: 0.90, blue: 0.44)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(263)
                    ),
                    style: .init(lineWidth: ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(red: 1.00, green: 0.45, blue: 0.16).opacity(0.28),
                        radius: size * 0.014)

            if !compact {
                Image(systemName: "sparkle")
                    .font(.system(size: ringDiameter * 0.40, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: ringDiameter - ringLineWidth, height: ringDiameter - ringLineWidth)
        .position(x: ringCenterX, y: size / 2)
    }
}

@main
struct MakeIcon {
    /// name in the iconset -> pixel size
    static let entries: [(String, CGFloat)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024)
    ]

    @MainActor static func main() {
        guard CommandLine.arguments.count > 1 else {
            fputs("usage: makeicon <output.iconset>\n", stderr)
            exit(2)
        }
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for (name, pixels) in entries {
            let renderer = ImageRenderer(content: IconView(size: pixels))
            renderer.scale = 1
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                fputs("render failed for \(name)\n", stderr)
                exit(1)
            }
            try? png.write(to: out.appendingPathComponent("\(name).png"))
        }
        print("wrote \(entries.count) images to \(out.path)")
    }
}
