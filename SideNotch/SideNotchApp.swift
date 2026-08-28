import SwiftUI

@main
struct SideNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No window scene: the app's only UI is the floating panel created by
        // the delegate. `Settings` keeps SwiftUI happy without showing anything.
        Settings {
            EmptyView()
        }
    }
}
