import AppKit
import RadioCore
import Testing
@testable import ListenMoe

@MainActor
struct StatusBarTests {
    @Test func distinguishesStatusItemClicks() {
        #expect(StatusItemInteraction.resolve(type: .leftMouseUp) == .player)
        #expect(StatusItemInteraction.resolve(type: .rightMouseUp) == .contextMenu)
        #expect(StatusItemInteraction.resolve(type: .leftMouseUp, modifiers: .control) == .contextMenu)
        #expect(StatusItemInteraction.resolve(type: .leftMouseUp, modifiers: .command) == .player)
        #expect(StatusItemInteraction.resolve(type: nil) == .player)
    }

    @Test func contextMenuIsMinimalAndSettingsOnly() {
        let radio = RadioModel.shared
        let target = NSObject()
        let menu = StatusContextMenu(radio: radio, target: target)
        #expect(!menu.autoenablesItems)
        #expect(menu.items.allSatisfy { $0.view == nil })
        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            "Show Player", "Settings", "Visit LISTEN.moe", "Reconnect song info", "Quit LISTEN.moe",
        ])
        #expect(menu.item(withTitle: "Show Player")?.action == #selector(StatusBarController.openPlayer))
        #expect(menu.item(withTitle: "Reconnect song info")?.action == #selector(StatusBarController.reconnectMetadata))
        #expect(menu.item(withTitle: "Quit LISTEN.moe")?.keyEquivalent == "q")
        let settings = menu.item(withTitle: "Settings")?.submenu
        let stations = settings?.item(withTitle: "Station")?.submenu
        #expect(stations?.items.count == Station.allCases.count)
        #expect(stations?.item(withTitle: radio.station.name)?.state == .on)
        for station in Station.allCases {
            let item = stations?.item(withTitle: station.name)
            #expect(item?.representedObject as? String == station.rawValue)
            #expect(item?.target === target)
        }
        #expect(settings?.item(withTitle: "Discord Rich Presence…")?.target === target)
        #expect(settings?.item(withTitle: "Launch at login")?.state == (radio.launchAtLogin ? .on : .off))
        #expect(settings?.item(withTitle: "Play on launch")?.state == (radio.autoplay ? .on : .off))
        #expect(settings?.item(withTitle: "Song title in menu bar")?.state == (radio.showMenuBarTitle ? .on : .off))
        #expect(settings?.item(withTitle: "Romanized titles & names")?.state == (radio.romanized ? .on : .off))
        #expect(settings?.item(withTitle: "Identify anime / game / VN origins")?.state == (radio.autoDetectOrigins ? .on : .off))
    }

    @Test func settingsCheckmarksRefresh() {
        let radio = RadioModel.shared
        let originalAutoplay = radio.autoplay
        defer { radio.autoplay = originalAutoplay }
        let menu = StatusContextMenu(radio: radio, target: NSObject())
        radio.autoplay.toggle()
        menu.refresh()
        let settings = menu.item(withTitle: "Settings")?.submenu
        #expect(settings?.item(withTitle: "Play on launch")?.state == (radio.autoplay ? .on : .off))
    }

}
