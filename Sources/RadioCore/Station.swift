import Foundation

public enum Station: String, CaseIterable, Codable, Identifiable, Sendable {
    case jpop
    case kpop

    public var id: String { rawValue }
    public var name: String { self == .jpop ? "J-pop" : "K-pop" }
    public var tagline: String {
        self == .jpop ? "Japanese pop & anime radio" : "Korean pop radio"
    }

    // AVPlayer natively supports the official MP3 fallback, not Ogg/Vorbis.
    public var streamURL: URL {
        URL(string: "https://listen.moe/\(self == .kpop ? "kpop/" : "")fallback")!
    }

    public var gatewayURL: URL {
        URL(string: "wss://listen.moe/\(self == .kpop ? "kpop/" : "")gateway_v2")!
    }
}
