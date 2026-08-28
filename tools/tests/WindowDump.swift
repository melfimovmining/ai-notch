import CoreGraphics
import AppKit

/// Prints the live panel's on-screen frame and window level. Diagnostic.
@main
struct WindowDump {
  static func main() {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for s in NSScreen.screens {
        print("screen frame \(s.frame) visible \(s.visibleFrame) scale \(s.backingScaleFactor)")
    }
    for w in list where (w[kCGWindowOwnerName as String] as? String) == "SideNotch" {
        let b = w[kCGWindowBounds as String] as! [String: CGFloat]
        print("SideNotch window: x=\(b["X"]!) y=\(b["Y"]!) w=\(b["Width"]!) h=\(b["Height"]!) layer=\(w[kCGWindowLayer as String] ?? "?") alpha=\(w[kCGWindowAlpha as String] ?? "?")")
    }
    print("expected panel size: \(Layout.panelWidth) x \(Layout.panelHeight)")
    
  }
}
