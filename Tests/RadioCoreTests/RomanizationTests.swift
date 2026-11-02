import Foundation
import Testing
import RadioCore

struct RomanizationTests {
    @Test func missingRomajiInLiveMetadataUsesJapaneseReadings() throws {
        let message = try JSONDecoder().decode(GatewayMessage.self, from: Data(#"""
        {"op":1,"t":"TRACK_UPDATE","d":{
            "song":{"id":9674,"title":"双糸","titleRomaji":null,
                "albums":[{"id":1553,"name":"綴 - EP","nameRomaji":null}],
                "artists":[{"id":663,"name":"binaria","nameRomaji":null}]},
            "lastPlayed":[{"id":749,"title":"秋のあなたの空遠く","titleRomaji":null}]
        }}
        """#.utf8))
        guard case .trackUpdate(let update) = message else {
            Issue.record("Expected track update")
            return
        }
        #expect(update.song.displayTitle(romanized: true) == "sou ito")
        #expect(update.song.albumName(romanized: true) == "tsudzuri - EP")
        #expect(update.song.artistName(romanized: true) == "binaria")
        #expect(update.lastPlayed.first?.displayTitle(romanized: true) == "aki no anata no sora tooku")
        #expect(update.song.displayTitle(romanized: false) == "双糸")
        #expect(update.song.titleRomaji == nil)
    }

    @Test(arguments: [
        #"{"id":1,"title":"赤いリボン"}"#,
        #"{"id":1,"title":"赤いリボン","titleRomaji":null}"#,
        #"{"id":1,"title":"赤いリボン","titleRomaji":""}"#,
        #"{"id":1,"title":"赤いリボン","titleRomaji":"  "}"#,
    ])
    func omittedNullAndBlankRomajiUseTheSameFallback(json: String) throws {
        let track = try decodeTrack(json)
        #expect(track.displayTitle(romanized: true) == "akai ribon")
        #expect(track.displayTitle(romanized: false) == "赤いリボン")
    }

    @Test func creditsAndOriginsUseTheSameFallback() throws {
        let track = try decodeTrack(#"""
        {"id":1,"title":"Test",
         "artists":[{"id":2,"name":"小倉唯","nameRomaji":null}],
         "albums":[{"id":3,"name":"東京物語","nameRomaji":"  "}],
         "sources":[{"id":4,"name":"進撃の巨人"}]}
        """#)
        #expect(track.artistName(romanized: true) == "ogura yui")
        #expect(track.albumName(romanized: true) == "toukyou monogatari")
        #expect(track.sources.first?.displayName(romanized: true) == "shingeki no kyojin")
        #expect(SongOrigin.stationSources(for: track).first?.displayName(romanized: true) == "shingeki no kyojin")
        #expect(track.artistName(romanized: false) == "小倉唯")
        #expect(track.albumName(romanized: false) == "東京物語")
    }

    @Test func suppliedRomajiAlwaysWinsOverInferredProperNames() throws {
        let track = try decodeTrack(#"""
        {"id":1,"title":"曇天羊","titleRomaji":"Donten Hitsuji",
         "artists":[{"id":2,"name":"角巻わため","nameRomaji":"Tsunomaki Watame"}]}
        """#)
        #expect(track.displayTitle(romanized: true) == "Donten Hitsuji")
        #expect(track.artistName(romanized: true) == "Tsunomaki Watame")
        let origin = SongOrigin(name: "進撃の巨人", nameRomaji: "Attack on Titan")
        #expect(origin.displayName(romanized: true) == "Attack on Titan")
    }

    @Test func kanaAndKoreanAreRomanizedWithoutKanji() throws {
        let kana = try decodeTrack(#"{"id":1,"title":"ひらがな カタカナ"}"#)
        #expect(kana.displayTitle(romanized: true) == "hiragana katakana")
        let korean = try decodeTrack(#"{"id":2,"title":"데이식스"}"#)
        #expect(korean.displayTitle(romanized: true) == "deisigseu")
        #expect(korean.displayTitle(romanized: false) == "데이식스")
    }

    @Test func preservesExistingLatinTextWhitespaceAndPunctuation() throws {
        let latin = try decodeTrack(#"{"id":1,"title":"🎵 DAY6 / EP vol.1"}"#)
        #expect(latin.displayTitle(romanized: true) == latin.title)
        let mixed = try decodeTrack(#"{"id":2,"title":"🎵 東京 物語！\n小倉唯 / Guest"}"#)
        #expect(mixed.displayTitle(romanized: true) == "🎵 toukyou monogatari！\nogura yui / Guest")
    }

    @Test func fallbackDoesNotReplaceStoredMetadata() throws {
        let track = try decodeTrack(#"{"id":1,"title":"赤いリボン","titleRomaji":null}"#)
        let saved = SavedTrack(track: track, station: .jpop)
        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(SavedTrack.self, from: data)
        #expect(decoded.track.title == "赤いリボン")
        #expect(decoded.track.titleRomaji == nil)
        #expect(decoded.track.displayTitle(romanized: true) == "akai ribon")
    }

    private func decodeTrack(_ json: String) throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data(json.utf8))
    }
}
