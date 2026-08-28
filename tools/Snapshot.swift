import SwiftUI
import AppKit

/// Renders NotchView offscreen to a PNG so the layout can be checked without
/// launching the app. Not part of the app target.
@main
struct Snapshot {
    @MainActor static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "snapshot.png"
        let hover = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : nil

        // Third argument: a Claude Code status line payload to render live.
        var metrics = Metric.samples
        if CommandLine.arguments.count > 3 {
            let url = URL(fileURLWithPath: CommandLine.arguments[3])
            do {
                let payload = try StatusLinePayload.decode(try Data(contentsOf: url))
                metrics = UsageMapper.metrics(from: payload)
                for m in metrics {
                    print("  \(m.id): \(m.percentText)  title=\"\(m.title)\"")
                    for r in m.rows {
                        print("      \(r.label) | \(r.meta) | \(r.caption)")
                    }
                }
            } catch {
                fputs("payload decode failed: \(error)\n", stderr); exit(1)
            }
        }

        let view = ZStack {
            LinearGradient(colors: [Color(red: 0.35, green: 0.62, blue: 0.75),
                                    Color(red: 0.20, green: 0.35, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            NotchView(metrics: metrics,
                      state: PanelState(expanded: ProcessInfo.processInfo.environment["SNAPSHOT_COLLAPSED"] == nil),
                      previewHover: hover)
        }
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("render failed\n", stderr); exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
