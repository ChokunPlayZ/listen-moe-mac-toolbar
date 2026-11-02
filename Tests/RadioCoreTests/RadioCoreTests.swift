import Foundation
import Testing
@testable import RadioCore

struct RadioCoreTests {
    private let decoder = JSONDecoder()

    @Test func stationEndpoints() {
        #expect(Station.jpop.streamURL.absoluteString == "https://listen.moe/fallback")
        #expect(Station.kpop.streamURL.absoluteString == "https://listen.moe/kpop/fallback")
        #expect(Station.jpop.gatewayURL.absoluteString == "wss://listen.moe/gateway_v2")
        #expect(Station.kpop.gatewayURL.absoluteString == "wss://listen.moe/kpop/gateway_v2")
    }

    @Test func welcomeAndHeartbeatAcknowledgement() throws {
        let hello = try decodeMessage(#"{"op":0,"d":{"heartbeat":35000}}"#)
        guard case .hello(let interval) = hello else {
            Issue.record("Expected hello")
            return
        }
        #expect(interval == 35)
        guard case .heartbeatAcknowledged = try decodeMessage(#"{"op":10}"#) else {
            Issue.record("Expected acknowledgement")
            return
        }
    }

    @Test(arguments: [0, -1, 999, 120001])
    func rejectsInvalidHeartbeat(milliseconds: Int) {
        #expect(throws: DecodingError.self) {
            try decodeMessage("{\"op\":0,\"d\":{\"heartbeat\":\(milliseconds)}}")
        }
    }

    @Test func ignoresUnrelatedEvents() throws {
        for raw in [#"{"op":100,"d":{}}"#, #"{"op":1,"t":"NOTIFICATION","d":{}}"#] {
            guard case .ignored = try decodeMessage(raw) else {
                Issue.record("Unrelated event must be ignored")
                return
            }
        }
    }

    @Test func decodesTrackUpdate() throws {
        let message = try decodeMessage("""
        {"op":1,"t":"TRACK_UPDATE","d":{
            "song":{
                "id":27913,"title":"曇天羊","titleRomaji":"Donten Hitsuji",
                "artists":[{"id":7068,"name":"角巻わため","nameRomaji":"Tsunomaki Watame","image":null}],
                "albums":[{"id":5958,"name":"わためのうた vol.1","image":"わためのうた-vol-1_cover_jpop.jpg"}],
                "duration":235
            },
            "startTime":"2026-11-02T18:03:23.521Z",
            "lastPlayed":[],"listeners":92,"requester":{"name":"a-listener"}
        }}
        """)
        guard case .trackUpdate(let update) = message else {
            Issue.record("Expected track update")
            return
        }
        #expect(update.song.id == 27913)
        #expect(update.song.displayTitle(romanized: true) == "Donten Hitsuji")
        #expect(update.song.displayTitle(romanized: false) == "曇天羊")
        #expect(update.song.artistName(romanized: true) == "Tsunomaki Watame")
        #expect(update.song.albumName(romanized: false) == "わためのうた vol.1")
        #expect(update.song.artworkURL?.host == "cdn.listen.moe")
        #expect(update.song.artworkURL?.path.hasPrefix("/covers/") == true)
        #expect(update.startTime != nil)
        #expect(update.listeners == 92)
        #expect(update.requester?.name == "a-listener")
    }

    @Test(arguments: ["2026-11-02T18:03:23Z", "2026-11-02T18:03:23.521Z"])
    func supportsBothTimestampFormats(timestamp: String) throws {
        let message = try decodeMessage("""
        {"op":1,"t":"TRACK_UPDATE_REQUEST","d":{
            "song":{"id":1,"title":"Test"},"startTime":"\(timestamp)"
        }}
        """)
        guard case .trackUpdate(let update) = message else {
            Issue.record("Expected track update")
            return
        }
        #expect(update.startTime != nil)
    }

    @Test func minimalTrackAndMissingMetadata() throws {
        let track = try decodeTrack(#"{"id":1,"title":"A song","titleRomaji":"  "}"#)
        #expect(track.displayTitle(romanized: true) == "A song")
        #expect(track.artistName(romanized: true) == "Unknown artist")
        #expect(track.albumName(romanized: true) == nil)
        #expect(track.duration == 0)
        #expect(track.artworkURL == nil)
    }

    @Test func nullCreditNameDoesNotDiscardLiveTrackUpdate() throws {
        let message = try decodeMessage("""
        {"op":1,"t":"TRACK_UPDATE","d":{
            "song":{"id":7780,"title":"ひび割れた鏡","duration":271},
            "startTime":"2026-11-02T19:13:34.166Z",
            "lastPlayed":[{"id":9950,"title":"TRINITY×SEVENTH＋HEAVEN","duration":240,
                "sources":[{"id":719,"name":null,"nameRomaji":"Trinity Seven","image":null}]}]
        }}
        """)
        guard case .trackUpdate(let update) = message else {
            Issue.record("Expected track update")
            return
        }
        #expect(update.startedAt != nil)
        #expect(update.song.id == 7780)
        #expect(update.lastPlayed.first?.sources.first?.name == "Trinity Seven")
    }

    @Test func unnamedCreditsRemainSafeToDisplay() throws {
        let track = try decodeTrack("""
        {"id":1,"title":"Test","artists":[{"id":2,"name":null}],
         "albums":[{"id":3,"name":null}],"sources":[{"id":4,"name":null}]}
        """)
        #expect(track.artistName(romanized: false) == "Unknown artist")
        #expect(track.albumName(romanized: false) == nil)
        #expect(SongOrigin.stationSources(for: track).isEmpty)
    }

    @Test func artistArtworkFallbackAndSafeFilenames() throws {
        let track = try decodeTrack("""
        {"id":1,"title":"Test","duration":-1,
        "albums":[{"id":1,"name":"Album","image":"../invalid.jpg"}],
        "artists":[{"id":2,"name":"Artist","image":"artist photo.jpg"}]}
        """)
        #expect(track.duration == 0)
        #expect(track.artworkURL?.absoluteString == "https://cdn.listen.moe/artists/artist%20photo.jpg")
    }

    @Test func savedSongsRoundTripAndStationIdentity() throws {
        let track = try decodeTrack(#"{"id":42,"title":"Test","duration":120}"#)
        let jpop = SavedTrack(track: track, station: .jpop)
        let kpop = SavedTrack(track: track, station: .kpop)
        #expect(jpop.id != kpop.id)
        let encoded = try JSONEncoder().encode([jpop, kpop])
        #expect(try decoder.decode([SavedTrack].self, from: encoded) == [jpop, kpop])
    }

    @Test func liveTimelineClampsAndDoesNotSeek() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(RadioTimeline.elapsed(since: start, duration: 120, now: start.addingTimeInterval(-5)) == 0)
        #expect(RadioTimeline.elapsed(since: start, duration: 120, now: start.addingTimeInterval(500)) == 120)
        #expect(RadioTimeline.progress(since: start, duration: 120, now: start.addingTimeInterval(60)) == 0.5)
        #expect(RadioTimeline.progress(since: start, duration: 0) == 0)
        #expect(RadioTimeline.elapsed(since: nil, duration: 120) == 0)
        #expect(RadioTimeline.timestamp(261) == "4:21")
        #expect(RadioTimeline.timestamp(-2) == "0:00")
        #expect(RadioTimeline.timestamp(.infinity) == "0:00")
    }

    private func decodeMessage(_ json: String) throws -> GatewayMessage {
        try decoder.decode(GatewayMessage.self, from: Data(json.utf8))
    }

    private func decodeTrack(_ json: String) throws -> Track {
        try decoder.decode(Track.self, from: Data(json.utf8))
    }
}
