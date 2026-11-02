import Foundation
import Testing
import RadioCore

struct TrackLinkTests {
    @Test func opensNativeAppleMusicSearchWithOriginalTitleAndArtists() throws {
        let track = try decode("""
        {"id":1,"title":"赤いリボン","titleRomaji":"Akai Ribbon",
         "artists":[{"id":2,"name":"小倉唯","nameRomaji":"Yui Ogura"}]}
        """)
        let components = try #require(URLComponents(url: track.appleMusicSearchURL(), resolvingAgainstBaseURL: false))
        #expect(components.scheme == "music")
        #expect(components.host == "music.apple.com")
        #expect(components.path == "/search")
        #expect(components.queryItems == [URLQueryItem(name: "term", value: "赤いリボン 小倉唯")])
    }

    @Test func providesWebFallbackWithoutChoosingAStorefront() throws {
        let track = try decode(#"{"id":1,"title":"Test"}"#)
        let components = try #require(URLComponents(
            url: track.appleMusicSearchURL(openInApp: false), resolvingAgainstBaseURL: false
        ))
        #expect(components.scheme == "https")
        #expect(components.host == "music.apple.com")
        #expect(components.path == "/search")
        #expect(components.queryItems?.first?.value == "Test")
        #expect(!components.url!.absoluteString.contains("Unknown"))
    }

    @Test func encodesSpecialCharactersAndIncludesEveryArtist() throws {
        let track = try decode("""
        {"id":1,"title":"A&B + #1?","artists":[{"id":2,"name":"歌手"},{"id":3,"name":"Guest"}]}
        """)
        let url = track.appleMusicSearchURL()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.value == "A&B + #1? 歌手 Guest")
        #expect(components.fragment == nil)
        #expect(url.absoluteString.contains("%2B"))
    }

    private func decode(_ json: String) throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data(json.utf8))
    }
}
