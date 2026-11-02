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
        #expect(settings?.item(withTitle: "Furigana for Japanese text")?.state == (radio.furigana ? .on : .off))
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

    @Test func furiganaSettingPersistsWithoutOverridingRomanization() {
        let radio = RadioModel.shared
        let originalFurigana = radio.furigana
        let originalRomanized = radio.romanized
        defer {
            radio.furigana = originalFurigana
            radio.romanized = originalRomanized
        }
        radio.romanized = true
        radio.furigana = true
        #expect(radio.usesRomanizedPlayerText)
        #expect(UserDefaults.standard.bool(forKey: "furigana"))
        let menu = StatusContextMenu(radio: radio, target: NSObject())
        let settings = menu.item(withTitle: "Settings")?.submenu
        #expect(settings?.item(withTitle: "Furigana for Japanese text")?.state == .on)
        radio.furigana = false
        menu.refresh()
        #expect(radio.usesRomanizedPlayerText)
        #expect(settings?.item(withTitle: "Furigana for Japanese text")?.state == .off)
    }

    @Test(arguments: [false, true], [false, true])
    func playerMetadataRespectsRomanization(romanized: Bool, furigana: Bool) throws {
        let radio = RadioModel.shared
        let originalRomanized = radio.romanized
        let originalFurigana = radio.furigana
        defer {
            radio.romanized = originalRomanized
            radio.furigana = originalFurigana
        }
        radio.romanized = romanized
        radio.furigana = furigana
        let track = try JSONDecoder().decode(Track.self, from: Data(#"""
        {"id":1,"title":"赤いリボン","titleRomaji":"Akai Ribbon",
         "artists":[{"id":2,"name":"小倉唯","nameRomaji":"Yui Ogura"}],
         "albums":[{"id":3,"name":"東京物語","nameRomaji":"Tokyo Monogatari"}],
         "sources":[{"id":4,"name":"進撃の巨人","nameRomaji":"Shingeki no Kyojin"}]}
        """#.utf8))
        #expect(radio.usesRomanizedPlayerText == romanized)
        #expect(track.displayTitle(romanized: radio.usesRomanizedPlayerText) == (romanized ? "Akai Ribbon" : "赤いリボン"))
        #expect(track.artistName(romanized: radio.usesRomanizedPlayerText) == (romanized ? "Yui Ogura" : "小倉唯"))
        #expect(track.albumName(romanized: radio.usesRomanizedPlayerText) == (romanized ? "Tokyo Monogatari" : "東京物語"))
        #expect(track.sources.first?.displayName(romanized: radio.usesRomanizedPlayerText) == (romanized ? "Shingeki no Kyojin" : "進撃の巨人"))
        let missingRomaji = try JSONDecoder().decode(Track.self, from: Data(
            #"{"id":5,"title":"赤いリボン","titleRomaji":null}"#.utf8
        ))
        #expect(missingRomaji.displayTitle(romanized: radio.usesRomanizedPlayerText) == (romanized ? "akai ribon" : "赤いリボン"))
    }
}
