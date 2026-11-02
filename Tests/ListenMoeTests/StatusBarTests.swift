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
        let textDisplay = settings?.item(withTitle: "Text display")?.submenu
        #expect(textDisplay?.items.map(\.title) == ["Romaji", "Furigana"])
        #expect(textDisplay?.item(withTitle: radio.textDisplayMode.title)?.state == .on)
        for mode in TextDisplayMode.allCases {
            let item = textDisplay?.item(withTitle: mode.title)
            #expect(item?.representedObject as? String == mode.rawValue)
            #expect(item?.action == #selector(StatusBarController.selectTextDisplay(_:)))
            #expect(item?.target === target)
        }
        #expect(settings?.item(withTitle: "Romanized titles & names") == nil)
        #expect(settings?.item(withTitle: "Furigana for Japanese text") == nil)
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

    @Test func textDisplayChoiceIsExclusiveAndPersists() throws {
        let radio = RadioModel.shared
        let originalMode = radio.textDisplayMode
        defer { radio.textDisplayMode = originalMode }
        let controller = StatusBarController(radio: radio)
        defer { controller.shutdown() }
        let menu = StatusContextMenu(radio: radio, target: controller)
        let textDisplay = try #require(menu.item(withTitle: "Settings")?.submenu?.item(withTitle: "Text display")?.submenu)

        // Re-selecting the active mode must not leave both modes off.
        for mode in [TextDisplayMode.furigana, .furigana, .romaji, .romaji] {
            let item = try #require(textDisplay.item(withTitle: mode.title))
            controller.selectTextDisplay(item)
            menu.refresh()
            #expect(radio.textDisplayMode == mode)
            #expect(radio.romanized == (mode == .romaji))
            #expect(radio.furigana == (mode == .furigana))
            #expect(radio.romanized != radio.furigana)
            #expect(UserDefaults.standard.string(forKey: "textDisplayMode") == mode.rawValue)
            #expect(TextDisplayMode.load(from: .standard) == mode)
            #expect(item.state == .on)
            #expect(textDisplay.items.filter { $0.state == .on }.count == 1)
        }
    }

    @Test(arguments: TextDisplayMode.allCases)
    func playerMetadataRespectsTextDisplayMode(mode: TextDisplayMode) throws {
        let radio = RadioModel.shared
        let originalMode = radio.textDisplayMode
        defer { radio.textDisplayMode = originalMode }
        radio.textDisplayMode = mode
        let romanized = mode == .romaji
        let track = try JSONDecoder().decode(Track.self, from: Data(#"""
        {"id":1,"title":"赤いリボン","titleRomaji":"Akai Ribbon",
         "artists":[{"id":2,"name":"小倉唯","nameRomaji":"Yui Ogura"}],
         "albums":[{"id":3,"name":"東京物語","nameRomaji":"Tokyo Monogatari"}],
         "sources":[{"id":4,"name":"進撃の巨人","nameRomaji":"Shingeki no Kyojin"}]}
        """#.utf8))
        #expect(radio.romanized == romanized)
        #expect(track.displayTitle(romanized: radio.romanized) == (romanized ? "Akai Ribbon" : "赤いリボン"))
        #expect(track.artistName(romanized: radio.romanized) == (romanized ? "Yui Ogura" : "小倉唯"))
        #expect(track.albumName(romanized: radio.romanized) == (romanized ? "Tokyo Monogatari" : "東京物語"))
        #expect(track.sources.first?.displayName(romanized: radio.romanized) == (romanized ? "Shingeki no Kyojin" : "進撃の巨人"))
        let missingRomaji = try JSONDecoder().decode(Track.self, from: Data(
            #"{"id":5,"title":"赤いリボン","titleRomaji":null}"#.utf8
        ))
        #expect(missingRomaji.displayTitle(romanized: radio.romanized) == (romanized ? "akai ribon" : "赤いリボン"))
    }
}
