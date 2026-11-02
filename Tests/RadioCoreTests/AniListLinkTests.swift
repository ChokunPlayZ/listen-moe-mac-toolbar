import Foundation
import RadioCore
import Testing

struct AniListLinkTests {
    @Test func taggedSourceIsClickableWithoutWikidataMatch() throws {
        let origin = SongOrigin(name: "進撃の巨人", nameRomaji: "Shingeki no Kyojin")
        #expect(origin.catalogURL == nil)
        let url = try #require(AniListLink.destination(for: [origin], track: nil))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "https")
        #expect(parts.host == "anilist.co")
        #expect(parts.path == "/search/anime")
        #expect(parts.queryItems == [URLQueryItem(name: "search", value: "Shingeki no Kyojin")])
    }

    @Test(arguments: [OriginKind.manga, .lightNovel])
    func writtenSourcesUseMangaSearch(kind: OriginKind) throws {
        let url = try #require(AniListLink.destination(for: [SongOrigin(name: "Test", kinds: [kind])], track: nil))
        #expect(url.path == "/search/manga")
    }

    @Test func animeAdaptationsUseAnimeSearch() throws {
        let url = try #require(AniListLink.destination(
            for: [SongOrigin(name: "Test", kinds: [.anime, .lightNovel], catalogID: "Q1")], track: nil
        ))
        #expect(url.host == "anilist.co")
        #expect(url.path == "/search/anime")
    }

    @Test func unknownSourceStillAllowsManualSearchWithoutClaimingAMatch() throws {
        let track = try JSONDecoder().decode(Track.self, from: Data(#"{"id":1,"title":"曲","titleRomaji":"Song"}"#.utf8))
        let url = try #require(AniListLink.destination(for: [], track: track))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Song")
        #expect(AniListLink.destination(for: [], track: nil) == nil)
    }

    @Test func encodesJapaneseAndSpecialCharactersWithoutChangingDestination() throws {
        let name = "日本語 + A&B #1?"
        let url = try #require(AniListLink.destination(for: [SongOrigin(name: name)], track: nil))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "anilist.co")
        #expect(parts.queryItems == [URLQueryItem(name: "search", value: name)])
        #expect(parts.fragment == nil)
        #expect(url.absoluteString.contains("%2B"))
    }
}
