import AppKit

@main
@MainActor
enum ListenMoeApp {
    static func main() {
        // A Settings-only SwiftUI App opens its settings window at launch.
        // AppKit owns the lifecycle; windows are presented only by user actions.
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()
        statusBar = StatusBarController(radio: RadioModel.shared)
        RadioModel.shared.start()
    }

    func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit LISTEN.moe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            .target = NSApp
        mainMenu.addItem(withTitle: "LISTEN.moe", action: nil, keyEquivalent: "").submenu = applicationMenu

        // Keep standard text-editing shortcuts in the hosted settings window.
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        mainMenu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu
        return mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBar?.shutdown()
        RadioModel.shared.shutdown()
    }
}
