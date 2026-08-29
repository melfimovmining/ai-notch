import AppKit
import SwiftUI

/// A borderless, transparent, always-on-top panel that never takes focus.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true

        // Above ordinary windows, and present on every Space and over full-screen apps.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Transparent chrome; the shadow is drawn in SwiftUI so it can follow the shape.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    // Borderless windows refuse key status by default; allow it so the context
    // menu behaves, without ever stealing focus from the frontmost app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Content view that only claims mouse events over the black bar. Without this
/// the transparent remainder of the panel would block clicks on whatever is
/// underneath it.
final class PassthroughView: NSView {
    /// Interactive region, in this view's own (bottom-left origin) coordinates.
    var interactiveRect: NSRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    // SideNotch is an accessory app and never becomes active, so every click is
    // a "first mouse". Without this the first click would only focus the panel.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Same reason as above, for the SwiftUI content that actually gets hit.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Owns the panel: builds it, hosts the SwiftUI view, and keeps it parked at the
/// top-right of the screen across display changes.
@MainActor
final class NotchPanelController: NSObject, NSMenuDelegate {
    private let panel: NotchPanel
    private let container: PassthroughView
    private let state: PanelState

    /// How forgiving the bar's edge is when deciding the pointer has left.
    private let pointerMargin: CGFloat = 6
    /// How often we ask where the pointer is while expanded.
    private let pollInterval: TimeInterval = 0.15

    private var watchdog = HoverWatchdog()
    private var pointerTimer: Timer?
    private var menuIsOpen = false

    /// Gap between the notch and the right edge of the screen.
    private let edgeInset: CGFloat = 0
    /// Gap between the menu bar and the top of the notch.
    private let topInset: CGFloat = 0

    private let cost: CostMonitor

    init(monitor: UsageMonitor, cost: CostMonitor, state: PanelState) {
        self.state = state
        self.cost = cost
        let size = NSSize(width: Layout.panelWidth, height: Layout.panelHeight)
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: size))

        container = PassthroughView(frame: NSRect(origin: .zero, size: size))
        super.init()
        container.autoresizingMask = [.width, .height]

        let hosting = ClickThroughHostingView(
            rootView: NotchRootView(monitor: monitor, cost: cost, state: state))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        container.addSubview(hosting)

        panel.contentView = container
        applyInteractiveRect(expanded: state.isExpanded)
        state.onChange = { [weak self] expanded in
            self?.applyInteractiveRect(expanded: expanded)
        }

        // The bar is exactly as tall as its rings, so gaining or losing the
        // spend ring means resizing and re-parking the whole panel.
        Layout.ringCount = cost.metric == nil ? 3 : 4
        cost.onRingCountChange = { [weak self] in
            Layout.ringCount = cost.metric == nil ? 3 : 4
            self?.reposition()
            self?.applyInteractiveRect(expanded: self?.state.isExpanded ?? false)
        }

        let menu = NSMenu()
        let keyItem = NSMenuItem(title: "Set Admin API Key…",
                                 action: #selector(setAdminKey),
                                 keyEquivalent: "")
        keyItem.target = self
        menu.addItem(keyItem)

        let budgetItem = NSMenuItem(title: "Set Credit Balance…",
                                    action: #selector(setBudget),
                                    keyEquivalent: "")
        budgetItem.target = self
        menu.addItem(budgetItem)
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Open at Login",
                                   action: #selector(toggleLoginItem),
                                   keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AI Notch",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        menu.delegate = self
        container.menu = menu

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on `.main` per the observer above.
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    /// Only the visible part of the panel — the bar, or just the tab when
    /// collapsed — claims mouse events; the rest stays click-through.
    private func applyInteractiveRect(expanded: Bool) {
        let frame = Layout.interactiveFrameInPanel(expanded: expanded)
        container.interactiveRect = NSRect(x: frame.minX,
                                           y: Layout.panelHeight - frame.maxY,
                                           width: frame.width,
                                           height: frame.height)
        expanded ? startWatchingPointer() : stopWatchingPointer()
    }

    // MARK: - Auto-collapse

    /// The expanded bar in screen coordinates.
    var barScreenFrame: NSRect {
        let frame = Layout.notchFrameInPanel
        let origin = panel.frame.origin
        return NSRect(x: origin.x + frame.minX,
                      y: origin.y + (Layout.panelHeight - frame.maxY),
                      width: frame.width,
                      height: frame.height)
    }

    /// True when the pointer is on the bar, give or take `pointerMargin`.
    func pointerIsOnBar(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        barScreenFrame.insetBy(dx: -pointerMargin, dy: -pointerMargin).contains(location)
    }

    /// Polling beats `onHover` here: the app never activates, so mouse-exited
    /// events are not guaranteed once the pointer is over another app's window.
    private func startWatchingPointer() {
        guard pointerTimer == nil else { return }
        watchdog.reset()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            // Added to the main run loop below, so this fires on main.
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopWatchingPointer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        watchdog.reset()
    }

    private func checkPointer() {
        guard state.isExpanded else { return stopWatchingPointer() }

        // Don't yank the bar out from under an open context menu.
        guard !menuIsOpen else { return watchdog.reset() }

        if watchdog.shouldCollapse(pointerInside: pointerIsOnBar(), now: Date()) {
            state.isExpanded = false
        }
    }

    /// Refresh the checkmark each time the menu opens — the user can also flip
    /// this in System Settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let item = menu.items.first(where: { $0.action == #selector(toggleLoginItem) }) {
            item.state = LoginItem.isEnabled ? .on : .off
            item.toolTip = "Open at Login: \(LoginItem.statusDescription)"
        }
        if let item = menu.items.first(where: { $0.action == #selector(setBudget) }) {
            item.title = AdminCredentials.creditBalance.map {
                "Set Credit Balance… (\(CostMapper.money($0)))"
            } ?? "Set Credit Balance…"
        }
        if let item = menu.items.first(where: { $0.action == #selector(setAdminKey) }) {
            item.title = AdminCredentials.hasKey
                ? "Change Admin API Key…" : "Set Admin API Key…"
        }
    }

    // MARK: - Spend ring settings

    @objc private func setAdminKey() {
        let alert = NSAlert()
        alert.messageText = "Anthropic Admin API Key"
        alert.informativeText = """
        Usage and cost reports need an Admin API key (sk-ant-admin01-…), an \
        org:admin OAuth token, or a personal key that is not scoped to a \
        workspace. A workspace-scoped key will not work, and the Admin API is \
        unavailable for individual accounts.

        The key is stored in your Keychain.
        """
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-ant-admin01-…"
        field.stringValue = AdminCredentials.key ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if AdminCredentials.hasKey { alert.addButton(withTitle: "Remove") }

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            AdminCredentials.setKey(field.stringValue)
            cost.refresh()
            verifyKey(field.stringValue)
        case .alertThirdButtonReturn:
            AdminCredentials.setKey(nil)
            cost.refresh()
        default:
            break
        }
    }

    /// Calls the API once so a bad key is reported now, rather than as a silent
    /// "Unavailable" on the ring a minute later.
    private func verifyKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let start = CostMonitor.windowStart(anchor: AdminCredentials.balanceAnchor)

        Task { @MainActor in
            do {
                _ = try await AdminAPI.costReport(key: trimmed, from: start, to: Date())
            } catch let error as AdminAPIError {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "That key did not work"
                alert.informativeText = error.longDescription
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            } catch {
                NSLog("AI Notch: key check failed: %@", error.localizedDescription)
            }
        }
    }

    @objc private func setBudget() {
        let alert = NSAlert()
        alert.messageText = "API Credit Balance"
        alert.informativeText = """
        Enter the "Remaining balance" shown on the Console billing page. AI \
        Notch subtracts your API spend from it every minute, so the ring counts \
        down on its own.

        It cannot see credit purchases — Anthropic publishes no endpoint for \
        the balance or for top-ups — so re-enter this after you buy credits. \
        The ring tells you when that is due.
        """
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "35.10"
        if let balance = AdminCredentials.creditBalance {
            field.stringValue = String(format: "%.2f", balance)
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if AdminCredentials.hasBalance { alert.addButton(withTitle: "Clear") }

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let cleaned = field.stringValue
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
            if let value = Double(cleaned), value > 0 {
                // Setting the balance also stamps "as of now"; spend is counted
                // from that moment on.
                AdminCredentials.creditBalance = value
                cost.refresh()
            }
        case .alertThirdButtonReturn:
            AdminCredentials.creditBalance = nil
            cost.refresh()
        default:
            break
        }
    }

    @objc private func toggleLoginItem() {
        do {
            try LoginItem.toggle()
        } catch {
            NSLog("SideNotch: could not change the login item: %@", error.localizedDescription)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        watchdog.reset()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        watchdog.reset()
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    /// Parks the panel so the notch is flush with the right edge of the screen,
    /// starting just below the menu bar.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame

        // The notch's right edge sits at the screen edge; the panel extends
        // further left to make room for the card and shadows.
        let notchRight = screen.frame.maxX - edgeInset
        let originX = notchRight - Layout.panelWidth

        // The notch's top edge sits just under the menu bar; the panel adds
        // `shadowPad` above that.
        let notchTop = visible.maxY - topInset
        let originY = notchTop + Layout.shadowPad - Layout.panelHeight

        panel.setFrame(NSRect(x: originX,
                              y: originY,
                              width: Layout.panelWidth,
                              height: Layout.panelHeight),
                       display: true)
    }
}
