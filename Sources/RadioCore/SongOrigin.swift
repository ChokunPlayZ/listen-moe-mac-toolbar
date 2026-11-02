import Foundation

public enum OriginKind: String, Codable, CaseIterable, Sendable {
    case anime = "Anime"
    case game = "Game"
    case visualNovel = "Visual novel"
    case manga = "Manga"
    case lightNovel = "Light novel"
    case film = "Film"
    case television = "TV / drama"
}

public struct SongOrigin: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let nameRomaji: String?
    public let kinds: [OriginKind]
    public let catalogID: String?
    public let evidence: Evidence
    public var id: String { catalogID ?? name }

    public enum Evidence: String, Codable, Sendable {
        case stationTag, songRelationship
    }

    public init(name: String, nameRomaji: String? = nil, kinds: [OriginKind] = [], catalogID: String? = nil, evidence: Evidence = .stationTag) {
        self.name = name
        self.nameRomaji = nameRomaji
        self.kinds = kinds
        self.catalogID = catalogID
        self.evidence = evidence
    }

    public func displayName(romanized: Bool) -> String {
        romanized ? nameRomaji?.nonBlank ?? Romanization.fallback(for: name) : name
    }

    public var kindLabel: String {
        kinds.isEmpty ? "Source" : kinds.map(\.rawValue).joined(separator: " / ")
    }

    public var catalogURL: URL? {
        guard let catalogID, catalogID.first == "Q", catalogID.dropFirst().allSatisfy(\.isNumber), catalogID.count > 1 else { return nil }
        return URL(string: "https://www.wikidata.org/wiki/\(catalogID)")
    }

    public var attribution: String {
        let source = evidence == .stationTag
            ? "Source tagged by LISTEN.moe. Media type matched against Wikidata."
            : "Wikidata links this song and performer to this work."
        return kinds.count > 1
            ? source + " Multiple adaptations share this title; the exact adaptation is not confirmed."
            : source
    }

    public static func stationSources(for track: Track) -> [SongOrigin] {
        var seen = Set<String>()
        return track.sources.compactMap { source in
            guard !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(OriginMatching.normalize(source.name)).inserted else { return nil }
            return SongOrigin(name: source.name, nameRomaji: source.nameRomaji)
        }
    }
}

public enum OriginMatching {
    public static func normalize(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    public static func exactMatch(_ names: [String], _ candidates: [String]) -> Bool {
        let normalized = Set(names.map(normalize).filter { !$0.isEmpty })
        return candidates.contains { normalized.contains(normalize($0)) }
    }

    public static func kind(instanceOf: [String], genres: [String], description: String) -> OriginKind? {
        let types = Set(instanceOf)
        // Prefer structured facts to descriptive text, especially for adaptations.
        if types.contains("Q5") { return nil } // A person is never a media source.
        if types.contains("Q689445") || genres.contains("Q689445") { return .visualNovel }
        if types.contains("Q7889") { return .game }
        if !types.isDisjoint(with: ["Q63952888", "Q20650540", "Q220898"]) { return .anime }
        let subject = description.lowercased()
            .components(separatedBy: " based on")[0]
            .components(separatedBy: " adapted from")[0]
        if subject.contains("visual novel") { return .visualNovel }
        if subject.contains("video game") || subject.contains("computer game") { return .game }
        if subject.contains("anime") && ["series", "film", "animation", "television"].contains(where: subject.contains) { return .anime }
        if subject.contains("light novel") { return .lightNovel }
        if subject.contains("manga series") { return .manga }
        if subject.contains("film") || subject.contains("movie") { return .film }
        if subject.contains("television series") || subject.contains("television drama") { return .television }
        return nil
    }
}
