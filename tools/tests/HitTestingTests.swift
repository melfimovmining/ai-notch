import AppKit

/// Drives the real NotchPanelController and asks it what a click at a given
/// point would hit, in both states.
/// Verifies that clicks land on the tab (collapsed) or the bar (expanded)
/// and pass straight through the transparent rest of the panel.
@main
struct HitTestingTests {
    @MainActor static func main() {
        _ = NSApplication.shared

        let state = PanelState(expanded: false)          // start collapsed
        let monitor = UsageMonitor(directory: URL(fileURLWithPath: "/nonexistent"))
        let controller = NotchPanelController(monitor: monitor, state: state)
        controller.show()

        guard let panel = NSApp.windows.first(where: { $0 is NSPanel }),
              let container = panel.contentView as? PassthroughView else {
            print("FAIL: no panel"); exit(1)
        }

        // Window coordinates (origin bottom-left).
        let h = Layout.panelHeight
        let tabRect = Layout.tabFrameInPanel(width: Layout.tabHoverWidth)
        let tabPoint = NSPoint(x: tabRect.midX, y: h - tabRect.midY)
        let barPoint = NSPoint(x: Layout.notchFrameInPanel.midX, y: h - Layout.ringCenterY(1))
        let outsidePoint = NSPoint(x: 60, y: h / 2)      // transparent card area

        func hit(_ p: NSPoint) -> String {
            guard let v = container.hitTest(p) else { return "nil (click-through)" }
            return String(describing: type(of: v))
        }

        var failures = 0
        func check(_ label: String, _ actual: String, shouldPass: Bool) {
            let passthrough = actual.hasPrefix("nil")
            let ok = shouldPass ? !passthrough : passthrough
            print("  \(ok ? "PASS" : "FAIL") \(label): \(actual)")
            if !ok { failures += 1 }
        }

        print("collapsed:")
        check("click on tab reaches SwiftUI", hit(tabPoint), shouldPass: true)
        check("click where the bar would be passes through", hit(barPoint), shouldPass: false)
        check("click on empty panel passes through", hit(outsidePoint), shouldPass: false)

        state.toggle()                                    // the tap gesture does this
        print("expanded (after toggle):")
        check("click on bar reaches SwiftUI", hit(barPoint), shouldPass: true)
        check("click on tab area still reaches SwiftUI", hit(tabPoint), shouldPass: true)
        check("click on empty panel passes through", hit(outsidePoint), shouldPass: false)

        print("acceptsFirstMouse: container=\(container.acceptsFirstMouse(for: nil)) " +
              "hit=\((container.hitTest(tabPoint))?.acceptsFirstMouse(for: nil) ?? false)")
        print("panel canBecomeKey=\(panel.canBecomeKey) ignoresMouseEvents=\(panel.ignoresMouseEvents)")
        exit(failures == 0 ? 0 : 1)
    }
}
