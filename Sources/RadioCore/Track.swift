import Foundation

public struct Credit: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let nameRomaji: String?
    public let image: String?

    public func displayName(romanized: Bool) -> String {
        romanized ? nameRomaji?.nonBlank ?? name : name
    }
}

public struct Track: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let titleRomaji: String?
    public let artists: [Credit]
    public let albums: [Credit]
    public let sources: [Credit]
    public let duration: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case id, title, titleRomaji, artists, albums, sources, duration
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        titleRomaji = try values.decodeIfPresent(String.self, forKey: .titleRomaji)
        artists = try values.decodeIfPresent([Credit].self, forKey: .artists) ?? []
        albums = try values.decodeIfPresent([Credit].self, forKey: .albums) ?? []
        sources = try values.decodeIfPresent([Credit].self, forKey: .sources) ?? []
        duration = max(0, try values.decodeIfPresent(Double.self, forKey: .duration) ?? 0)
    }

    public func displayTitle(romanized: Bool) -> String {
        romanized ? titleRomaji?.nonBlank ?? title : title
    }

    public func artistName(romanized: Bool) -> String {
        let names = artists.map { $0.displayName(romanized: romanized) }
        return names.isEmpty ? "Unknown artist" : names.joined(separator: ", ")
    }

    public func albumName(romanized: Bool) -> String? {
        albums.first?.displayName(romanized: romanized)
    }

    public var artworkURL: URL? {
        if let image = albums.compactMap(\.image).first(where: Self.isSafeFilename) {
            return URL(string: "https://cdn.listen.moe/covers/")!.appendingPathComponent(image)
        }
        if let image = artists.compactMap(\.image).first(where: Self.isSafeFilename) {
            return URL(string: "https://cdn.listen.moe/artists/")!.appendingPathComponent(image)
        }
        return nil
    }

    private static func isSafeFilename(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.contains("/") && !value.contains("\\") && value != ".." && value != "."
    }
}

public struct SavedTrack: Codable, Identifiable, Equatable, Sendable {
    public let track: Track
    public let station: Station
    public let savedAt: Date
    public var id: String { "\(station.rawValue):\(track.id)" }

    public init(track: Track, station: Station, savedAt: Date = .now) {
        self.track = track
        self.station = station
        self.savedAt = savedAt
    }
}

extension String {
    var nonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

public enum RadioTimeline {
    public static func elapsed(since start: Date?, duration: TimeInterval, now: Date = .now) -> TimeInterval {
        guard let start else { return 0 }
        let elapsed = max(0, now.timeIntervalSince(start))
        return duration > 0 ? min(elapsed, duration) : elapsed
    }

    public static func progress(since start: Date?, duration: TimeInterval, now: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return elapsed(since: start, duration: duration, now: now) / duration
    }

    public static func timestamp(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "0:00" }
        let seconds = Int(min(max(0, interval), 359_999))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
