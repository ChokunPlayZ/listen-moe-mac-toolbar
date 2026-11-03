import AppKit
import Testing
@testable import ListenMoe

@MainActor
struct AppLaunchTests {
    @Test func appKitLifecyclePreservesQuitAndTextEditingShortcuts() throws {
        let application = NSApplication.shared
        let menu = AppDelegate().makeMainMenu()
        let applicationMenu = try #require(menu.items.first?.submenu)
        let quit = try #require(applicationMenu.item(withTitle: "Quit LISTEN.moe"))
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
        #expect(quit.keyEquivalent == "q")
        #expect(quit.target === application)

        let editMenu = try #require(menu.items.last?.submenu)
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            let item = try #require(editMenu.item(withTitle: title))
            #expect(item.action == action)
            #expect(item.keyEquivalent == key)
            #expect(item.target == nil)
        }
    }
}
