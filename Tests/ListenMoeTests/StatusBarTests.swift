import AppKit
import Foundation
import RadioCore
import SwiftUI
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

    @Test func menuIncludesSongInfoAndQuickActions() {
        let radio = RadioModel.shared
        let menu = StatusContextMenu(radio: radio, target: NSObject())
        #expect(!menu.autoenablesItems)
        #expect(menu.items.first?.view is NSHostingView<NowPlayingMenuView>)
        #expect(menu.items.contains { $0.view is NSHostingView<MenuVolumeView> })
        #expect(menu.items.contains { $0.view is NSHostingView<MenuPlaybackView> })
        #expect(menu.item(withTitle: "Show Player") != nil)
        #expect(menu.item(withTitle: "Play Radio") != nil)
        #expect(menu.item(withTitle: "Mute") != nil)
        #expect(menu.item(withTitle: "Copy Song & Artist")?.isEnabled == false)
        #expect(menu.item(withTitle: "Save Current Song")?.isEnabled == false)
        #expect(menu.item(withTitle: "Quit LISTEN.moe")?.keyEquivalent == "q")
        let stations = menu.item(withTitle: "Station")?.submenu
        #expect(stations?.items.count == Station.allCases.count)
        #expect(stations?.item(withTitle: radio.station.name)?.state == .on)
    }

    @Test func currentSongInfoIncludesArtistAndAlbum() throws {
        let track = try JSONDecoder().decode(Track.self, from: Data("""
        {"id":1,"title":"曲","titleRomaji":"Song",
         "artists":[{"id":2,"name":"歌手","nameRomaji":"Artist"}],
         "albums":[{"id":3,"name":"アルバム","nameRomaji":"Album"}]}
        """.utf8))
        let info = NowPlayingMenuInfo(track: track, station: .jpop, playbackState: .playing, romanized: true)
        #expect(info.heading == "Now playing · J-pop")
        #expect(info.title == "Song")
        #expect(info.artist == "Artist")
        #expect(info.album == "Album")
        let paused = NowPlayingMenuInfo(track: track, station: .kpop, playbackState: .stopped, romanized: false)
        #expect(paused.heading == "On air · K-pop")
        #expect(paused.title == "曲")
        #expect(paused.artist == "歌手")
    }

    @Test func missingMetadataShowsLoadingState() {
        let info = NowPlayingMenuInfo(track: nil, station: .jpop, playbackState: .buffering, romanized: true)
        #expect(info.title == "Fetching song info…")
        #expect(info.album == nil)
        let host = NSHostingView(rootView: NowPlayingMenuView(radio: RadioModel.shared))
        #expect(host.fittingSize == NSSize(width: 320, height: 200))
        let volume = NSHostingView(rootView: MenuVolumeView(radio: RadioModel.shared))
        #expect(volume.fittingSize == NSSize(width: 320, height: 42))
        let controls = NSHostingView(rootView: MenuPlaybackView(radio: RadioModel.shared, openPlayer: {}))
        #expect(controls.fittingSize == NSSize(width: 320, height: 54))
    }
}
