import Foundation

public enum AniListLink {
    public static func destination(for origins: [SongOrigin], track: Track?) -> URL? {
        let origin = origins.first { $0.name.nonBlank != nil || $0.nameRomaji?.nonBlank != nil }
        let query = origin?.nameRomaji?.nonBlank ?? origin?.name.nonBlank
            ?? track?.titleRomaji?.nonBlank ?? track?.title.nonBlank
        guard let query else { return nil }
        let kinds = origin?.kinds ?? []
        let manga = !kinds.contains(.anime) && (kinds.contains(.manga) || kinds.contains(.lightNovel))
        var url = URLComponents(string: "https://anilist.co/search/\(manga ? "manga" : "anime")")!
        url.queryItems = [URLQueryItem(name: "search", value: query)]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return url.url
    }
}
