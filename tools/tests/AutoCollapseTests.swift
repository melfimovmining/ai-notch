import AppKit

/// Verifies the auto-collapse timing rules, the bar's on-screen geometry,
/// and that an abandoned bar really does collapse itself.
@main
struct AutoCollapseTests {
    @MainActor static func main() {
        var failures = 0
        func check(_ label: String, _ ok: Bool) {
            print("  \(ok ? "PASS" : "FAIL") \(label)")
            if !ok { failures += 1 }
        }

        // ---- 1. Timing rules -------------------------------------------------
        print("watchdog (grace 0.6s):")
        var w = HoverWatchdog(grace: 0.6)
        let t0 = Date()
        check("pointer on bar -> stays open", !w.shouldCollapse(pointerInside: true, now: t0))
        check("just left -> still open", !w.shouldCollapse(pointerInside: false, now: t0.addingTimeInterval(0.1)))
        check("away 0.4s -> still open", !w.shouldCollapse(pointerInside: false, now: t0.addingTimeInterval(0.5)))
        check("away 0.7s -> COLLAPSE", w.shouldCollapse(pointerInside: false, now: t0.addingTimeInterval(0.8)))
        check("fires only once", !w.shouldCollapse(pointerInside: false, now: t0.addingTimeInterval(0.9)))

        var w2 = HoverWatchdog(grace: 0.6)
        _ = w2.shouldCollapse(pointerInside: false, now: t0)
        _ = w2.shouldCollapse(pointerInside: false, now: t0.addingTimeInterval(0.5))
        check("re-entering resets the countdown", !w2.shouldCollapse(pointerInside: true, now: t0.addingTimeInterval(0.55)))
        check("...and it does not fire at the old deadline",
              !w2.shouldCollapse(pointerInside: false, now: t0.addingTimeInterval(0.7)))

        // ---- 2. Geometry against the real panel ------------------------------
        _ = NSApplication.shared
        let state = PanelState(expanded: true)
        let controller = NotchPanelController(
            monitor: UsageMonitor(directory: URL(fileURLWithPath: "/nonexistent")),
            cost: CostMonitor(), state: state)
        controller.show()

        let bar = controller.barScreenFrame
        let screen = NSScreen.main!.frame
        let visible = NSScreen.main!.visibleFrame
        print("bar on screen: \(bar)")
        print("screen: \(screen)  visible: \(visible)")
        check("bar is flush with the right screen edge", abs(bar.maxX - screen.maxX) < 0.5)
        check("bar top sits at the menu bar bottom", abs(bar.maxY - visible.maxY) < 0.5)

        print("pointer tests:")
        check("centre of bar -> inside", controller.pointerIsOnBar(NSPoint(x: bar.midX, y: bar.midY)))
        check("6pt outside left edge -> inside (forgiving)",
              controller.pointerIsOnBar(NSPoint(x: bar.minX - 5, y: bar.midY)))
        check("40pt to the left (over the card) -> outside",
              !controller.pointerIsOnBar(NSPoint(x: bar.minX - 40, y: bar.midY)))
        check("far below the bar -> outside",
              !controller.pointerIsOnBar(NSPoint(x: bar.midX, y: bar.minY - 100)))

        // ---- 3. The timer actually collapses it ------------------------------
        guard !controller.pointerIsOnBar() else {
            print("live: SKIPPED — the pointer is on the bar, so staying open is correct")
            exit(failures == 0 ? 0 : 1)
        }
        print("live (pointer parked off the bar):")
        let deadline = Date().addingTimeInterval(3)
        while state.isExpanded && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        check("expanded bar auto-collapsed within 3s", !state.isExpanded)
        exit(failures == 0 ? 0 : 1)
    }
}
