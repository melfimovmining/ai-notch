import AppKit

/// Asks macOS which icon it resolves for a bundle and writes it to a PNG.
@main
struct IconDump {
    @MainActor static func main() {
        let path = CommandLine.arguments[1]
        let out = CommandLine.arguments[2]
        let icon = NSWorkspace.shared.icon(forFile: path)   // what Finder draws
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: out))
        print("reps offered: \(icon.representations.map { "\(Int($0.size.width))" }.joined(separator: ","))")
    }
}
