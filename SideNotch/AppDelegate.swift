import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchPanelController?
    private let monitor = UsageMonitor()
    private let state = PanelState.restored()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // `install.sh` runs the executable directly with one of these flags; do
        // the work, report, and exit before putting anything on screen.
        if let command = LoginItemCommand.parse(CommandLine.arguments) {
            exit(command.run())
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces: Info.plist already sets LSUIElement.
        NSApp.setActivationPolicy(.accessory)

        monitor.start()

        let controller = NotchPanelController(monitor: monitor, state: state)
        controller.show()
        self.controller = controller
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
