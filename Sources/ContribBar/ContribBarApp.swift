import AppKit
import SwiftUI

@main
struct ContribBarApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // Everything lives in the status item's panel; SwiftUI just needs a scene.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ContributionStore?
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon (also covers `swift run`, which has no Info.plist).
        NSApp.setActivationPolicy(.accessory)
        let store = ContributionStore()
        self.store = store
        statusController = StatusController(store: store)
    }
}
