import Foundation
/// Prints the interactive rects for both panel states. Diagnostic, not a test.
@main
struct GeometryDump { static func main() {
    for expanded in [true, false] {
        let f = Layout.interactiveFrameInPanel(expanded: expanded)
        print(String(format: "expanded=%@  x=%.0f y=%.0f w=%.0f h=%.0f  (right edge at %.0f = panelWidth %.0f)",
                     expanded ? "yes" : "no ", f.minX, f.minY, f.width, f.height, f.maxX, Layout.panelWidth))
    }
    print(String(format: "tab centre y=%.0f, notch centre y=%.0f (must match)", Layout.tabFrameInPanel().midY, Layout.contentCenterY))
} }
