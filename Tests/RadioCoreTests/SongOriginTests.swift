import Foundation
import Testing
@testable import RadioCore

struct SongOriginTests {
    private actor Fixture {
        let responses: [String: String]
        private(set) var count = 0
        init(_ responses: [String: String]) { self.responses = responses }
        func reply(_ request: URLRequest) throws -> Data {
            count += 1
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
            let key = query["search"] ?? query["ids"] ?? ""
            guard let json = responses[key] else { throw URLError(.badServerResponse) }
            return Data(json.utf8)
        }
    }

    @Test func matchesExactSourceAndCachesResult() async throws {
        let fixture = Fixture([
            "Test Anime": #"{"search":[{"id":"Q1"}]}"#,
            "Q1": #"{"entities":{"Q1":{"id":"Q1","labels":{"en":{"value":"Test Anime"}},"claims":{"P31":[{"mainsnak":{"datavalue":{"type":"wikibase-entityid","value":{"id":"Q63952888"}}}}]}}}}"#,
        ])
        let resolver = SongOriginResolver(cacheURL: nil, transport: { try await fixture.reply($0) })
        let track = try track(#"{"id":1,"title":"Song","sources":[{"id":2,"name":"Test Anime"}]}"#)
        let result = try await resolver.resolve(track: track, station: .jpop)
        #expect(result.count == 1)
        #expect(result.first?.kinds == [.anime])
        #expect(result.first?.catalogURL?.absoluteString == "https://www.wikidata.org/wiki/Q1")
        #expect(try await resolver.resolve(track: track, station: .jpop) == result)
        #expect(await fixture.count == 2)
    }

    @Test func doesNotMistakeSimilarTitleForExactMatch() async throws {
        let fixture = Fixture([
            "Test": #"{"search":[{"id":"Q1"}]}"#,
            "Q1": #"{"entities":{"Q1":{"id":"Q1","labels":{"en":{"value":"Test 2"}},"descriptions":{"en":{"value":"Japanese anime television series"}}}}}"#,
        ])
        let resolver = SongOriginResolver(cacheURL: nil, transport: { try await fixture.reply($0) })
        let result = try await resolver.resolve(track: track(#"{"id":1,"title":"Song","sources":[{"id":2,"name":"Test"}]}"#), station: .jpop)
        #expect(result.first?.name == "Test")
        #expect(result.first?.kinds.isEmpty == true)
        #expect(result.first?.catalogURL == nil)
    }

    @Test func verifiesPerformerBeforeUsingSongRelationships() async throws {
        let fixture = Fixture([
            "Song": #"{"search":[{"id":"Q1"}]}"#,
            "Q1": #"{"entities":{"Q1":{"id":"Q1","labels":{"en":{"value":"Song"}},"claims":{"P175":[{"mainsnak":{"datavalue":{"type":"wikibase-entityid","value":{"id":"Q2"}}}}],"P1441":[{"mainsnak":{"datavalue":{"type":"wikibase-entityid","value":{"id":"Q3"}}}}],"P577":[{"mainsnak":{"datavalue":{"type":"time","value":{"time":"+2020-01-01T00:00:00Z"}}}}]}}}}"#,
            "Q2": #"{"entities":{"Q2":{"id":"Q2","labels":{"en":{"value":"Artist"}}}}}"#,
            "Q3": #"{"entities":{"Q3":{"id":"Q3","labels":{"en":{"value":"Game"}},"claims":{"P31":[{"mainsnak":{"datavalue":{"type":"wikibase-entityid","value":{"id":"Q7889"}}}}]}}}}"#,
        ])
        let resolver = SongOriginResolver(cacheURL: nil, transport: { try await fixture.reply($0) })
        let song = try track(#"{"id":1,"title":"Song","artists":[{"id":2,"name":"Artist"}]}"#)
        let result = try await resolver.resolve(track: song, station: .jpop)
        #expect(result.first?.kinds == [.game])
        #expect(result.first?.evidence == .songRelationship)
        let differentArtist = try track(#"{"id":2,"title":"Song","artists":[{"id":3,"name":"Another Artist"}]}"#)
        #expect(try await resolver.resolve(track: differentArtist, station: .jpop).isEmpty)
    }

    @Test func classificationUsesSubjectNotAdaptationOrPerformer() {
        #expect(OriginMatching.kind(instanceOf: ["Q7889"], genres: ["Q689445"], description: "2009 visual novel game") == .visualNovel)
        #expect(OriginMatching.kind(instanceOf: ["Q63952888"], genres: [], description: "anime based on a visual novel") == .anime)
        #expect(OriginMatching.kind(instanceOf: ["Q7889"], genres: [], description: "video game based on an anime series") == .game)
        #expect(OriginMatching.kind(instanceOf: ["Q5"], genres: [], description: "anime film actor") == nil)
        #expect(!OriginMatching.exactMatch(["Test"], ["Test 2"]))
        #expect(OriginMatching.exactMatch(["ＳＴＥＩＮＳ；ＧＡＴＥ"], ["Steins;Gate"]))
    }

    @Test func retainsAmbiguityAndRejectsUnsafeLinks() {
        let origin = SongOrigin(name: "Shared title", kinds: [.anime, .visualNovel], catalogID: "Q1")
        #expect(origin.kindLabel == "Anime / Visual novel")
        #expect(origin.attribution.contains("not confirmed"))
        #expect(SongOrigin(name: "Test", catalogID: "Q1/../../bad").catalogURL == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LISTEN_MOE_LIVE_TESTS"] == "1"))
    func liveSongRelationship() async throws {
        let song = try track(#"{"id":-1,"title":"only my railgun","artists":[{"id":1,"name":"fripSide"}]}"#)
        let result = try await SongOriginResolver(cacheURL: nil).resolve(track: song, station: .jpop)
        #expect(result.contains { $0.kinds.contains(.anime) && $0.evidence == .songRelationship })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LISTEN_MOE_LIVE_TESTS"] == "1"))
    func liveGameAndVisualNovelSources() async throws {
        let resolver = SongOriginResolver(cacheURL: nil)
        let game = try track(#"{"id":-2,"title":"Test","sources":[{"id":1,"name":"Genshin Impact"}]}"#)
        let vn = try track(#"{"id":-3,"title":"Test","sources":[{"id":2,"name":"Steins;Gate"}]}"#)
        #expect(try await resolver.resolve(track: game, station: .jpop).contains { $0.kinds.contains(.game) })
        #expect(try await resolver.resolve(track: vn, station: .jpop).contains { $0.kinds.contains(.visualNovel) })
    }

    private func track(_ json: String) throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data(json.utf8))
    }
}
