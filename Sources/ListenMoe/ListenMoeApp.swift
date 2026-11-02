import AppKit
import SwiftUI

@main
@MainActor
struct ListenMoeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // AppKit owns the status item so left- and right-click can differ.
        Settings { DiscordSettingsView(radio: RadioModel.shared) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBar = StatusBarController(radio: RadioModel.shared)
        RadioModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBar?.shutdown()
        RadioModel.shared.shutdown()
    }
}
