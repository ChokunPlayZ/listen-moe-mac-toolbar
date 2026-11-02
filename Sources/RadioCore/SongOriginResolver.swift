import Foundation

/// Exact-name catalogue matching only. No fuzzy first-result or title-keyword guesses.
public actor SongOriginResolver {
    public typealias Transport = @Sendable (URLRequest) async throws -> Data
    private let transport: Transport
    private let cacheURL: URL?
    private var cache: [String: CacheEntry]

    private struct CacheEntry: Codable {
        let origins: [SongOrigin]
        let expires: Date
    }
    private enum LookupError: Error { case response, oversized, invalidEntity, service(String) }
    private struct APIErrorResponse: Decodable {
        struct ServiceError: Decodable { let code: String; let info: String }
        let error: ServiceError
    }

    public init(cacheURL: URL? = SongOriginResolver.defaultCacheURL, transport: @escaping Transport = SongOriginResolver.fetch) {
        self.cacheURL = cacheURL
        self.transport = transport
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let stored = try? JSONDecoder().decode([String: CacheEntry].self, from: data) {
            cache = stored.filter { $0.value.expires > .now }
        } else {
            cache = [:]
        }
    }

    public static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ListenMoe", isDirectory: true)
            .appendingPathComponent("song-origins-v1.json")
    }

    public static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LookupError.response }
        guard data.count <= 4_000_000 else { throw LookupError.oversized }
        return data
    }

    public func resolve(track: Track, station: Station) async throws -> [SongOrigin] {
        let key = "\(station.rawValue):\(track.id):\(track.title):\(track.artists.map(\.name).joined(separator: "|")):\(track.sources.map(\.name).joined(separator: "|"))"
        if let entry = cache[key], entry.expires > .now { return entry.origins }
        var origins = [SongOrigin]()
        let taggedSources = SongOrigin.stationSources(for: track)
        for source in taggedSources.prefix(4) {
            try Task.checkCancellation()
            let names = [source.name, source.nameRomaji].compactMap { $0 }
            let matches = try await findEntities(names: names)
            let kinds = OriginKind.allCases.filter { kind in matches.contains { $0.kind == kind } }
            origins.append(SongOrigin(
                name: source.name, nameRomaji: source.nameRomaji, kinds: kinds,
                catalogID: matches.first(where: { $0.kind != nil })?.id
            ))
        }
        origins.append(contentsOf: taggedSources.dropFirst(4))
        if origins.isEmpty {
            origins = try await findSongRelationships(track: track)
        }
        try Task.checkCancellation()
        let lifetime: TimeInterval = origins.isEmpty || origins.allSatisfy({ $0.kinds.isEmpty }) ? 86_400 : 30 * 86_400
        cache[key] = CacheEntry(origins: origins, expires: Date().addingTimeInterval(lifetime))
        saveCache()
        return origins
    }

    private func findEntities(names: [String]) async throws -> [Entity] {
        for name in names.reversed() where !name.isEmpty {
            let language: String
            if name.unicodeScalars.contains(where: { (0xac00...0xd7af).contains($0.value) }) {
                language = "ko"
            } else {
                language = name.unicodeScalars.contains(where: { (0x3040...0x9fff).contains($0.value) }) ? "ja" : "en"
            }
            let response: SearchResponse = try await request([
                "action": "wbsearchentities", "search": name, "language": language, "limit": "5", "type": "item",
            ])
            let found = try await entities(ids: response.search.map(\.id))
                .filter { OriginMatching.exactMatch(names, $0.names) }
            if !found.isEmpty { return found }
        }
        return []
    }

    private func findSongRelationships(track: Track) async throws -> [SongOrigin] {
        let songNames = [track.title, track.titleRomaji].compactMap { $0 }
        let artistNames = track.artists.flatMap { [$0.name, $0.nameRomaji].compactMap { $0 } }
        guard !artistNames.isEmpty else { return [] }
        let songs = try await findEntities(names: songNames)
        let performerIDs = songs.flatMap { $0.references("P175") }
        let performers = try await entities(ids: performerIDs)
        let matchingPerformerIDs = Set(performers.filter { OriginMatching.exactMatch(artistNames, $0.names) }.map(\.id))
        let verifiedSongs = songs.filter { !Set($0.references("P175")).isDisjoint(with: matchingPerformerIDs) }
        // P1441 = present in work. P361 = part of. Both are explicit relationships.
        let workIDs = verifiedSongs.flatMap { $0.references("P1441") + $0.references("P361") }
        let works = try await entities(ids: workIDs)
        return works.compactMap { work in
            guard let kind = work.kind, let name = work.labels["ja"]?.value ?? work.labels["en"]?.value else { return nil }
            return SongOrigin(name: name, nameRomaji: work.labels["en"]?.value, kinds: [kind], catalogID: work.id, evidence: .songRelationship)
        }
    }

    private func entities(ids: [String]) async throws -> [Entity] {
        let uniqueIDs = Array(Set(ids)).sorted().prefix(40)
        guard !uniqueIDs.isEmpty else { return [] }
        guard uniqueIDs.allSatisfy({ $0.first == "Q" && $0.count > 1 && $0.dropFirst().allSatisfy(\.isNumber) }) else {
            throw LookupError.invalidEntity
        }
        let response: EntityResponse = try await request([
            "action": "wbgetentities", "ids": uniqueIDs.joined(separator: "|"),
            "props": "labels|aliases|descriptions|claims", "languages": "en|ja|ko",
        ])
        return uniqueIDs.compactMap { response.entities[$0] }
    }

    private func request<Response: Decodable>(_ parameters: [String: String]) async throws -> Response {
        try Task.checkCancellation()
        var url = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        var query = parameters
        query["format"] = "json"
        query["maxlag"] = "10"
        url.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!, timeoutInterval: 12)
        request.setValue("ListenMoeMenuBar/1.0 (unofficial macOS LISTEN.moe client)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<2 {
            let data = try await transport(request)
            try Task.checkCancellation()
            if let response = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                if attempt == 0, ["maxlag", "ratelimited"].contains(response.error.code) {
                    try await Task.sleep(for: .seconds(5))
                    continue
                }
                throw LookupError.service(response.error.info)
            }
            return try JSONDecoder().decode(Response.self, from: data)
        }
        throw LookupError.response
    }

    private func saveCache() {
        cache = cache.filter { $0.value.expires > .now }
        if cache.count > 1_000 {
            cache = Dictionary(uniqueKeysWithValues: cache.sorted { $0.value.expires > $1.value.expires }.prefix(1_000).map { ($0.key, $0.value) })
        }
        guard let cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private struct SearchResponse: Decodable { let search: [SearchItem] }
    private struct SearchItem: Decodable { let id: String }
    private struct EntityResponse: Decodable { let entities: [String: Entity] }
    private struct TextValue: Decodable { let value: String }

    private struct Entity: Decodable {
        let id: String
        let labels: [String: TextValue]
        let aliases: [String: [TextValue]]
        let descriptions: [String: TextValue]
        let claims: [String: [Claim]]
        private enum CodingKeys: String, CodingKey { case id, labels, aliases, descriptions, claims }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            labels = try values.decodeIfPresent([String: TextValue].self, forKey: .labels) ?? [:]
            aliases = try values.decodeIfPresent([String: [TextValue]].self, forKey: .aliases) ?? [:]
            descriptions = try values.decodeIfPresent([String: TextValue].self, forKey: .descriptions) ?? [:]
            claims = try values.decodeIfPresent([String: [Claim]].self, forKey: .claims) ?? [:]
        }

        var names: [String] { labels.values.map(\.value) + aliases.values.flatMap { $0.map(\.value) } }
        func references(_ property: String) -> [String] {
            (claims[property] ?? []).filter { $0.rank != "deprecated" }.compactMap(\.entityID)
        }
        var kind: OriginKind? {
            OriginMatching.kind(instanceOf: references("P31"), genres: references("P136"), description: descriptions["en"]?.value ?? "")
        }
    }

    private struct Claim: Decodable {
        let rank: String?
        let entityID: String?
        private enum CodingKeys: String, CodingKey { case rank, mainsnak }
        private enum SnakKeys: String, CodingKey { case datavalue }
        private enum ValueKeys: String, CodingKey { case value, type }
        private struct Reference: Decodable { let id: String }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            rank = try values.decodeIfPresent(String.self, forKey: .rank)
            let snak = try values.nestedContainer(keyedBy: SnakKeys.self, forKey: .mainsnak)
            if snak.contains(.datavalue),
               let data = try? snak.nestedContainer(keyedBy: ValueKeys.self, forKey: .datavalue),
               (try? data.decode(String.self, forKey: .type)) == "wikibase-entityid" {
                entityID = try? data.decode(Reference.self, forKey: .value).id
            } else {
                entityID = nil
            }
        }
    }
}
