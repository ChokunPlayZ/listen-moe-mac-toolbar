import Foundation

public struct TrackUpdate: Decodable, Sendable {
    public let song: Track
    public let lastPlayed: [Track]
    public let listeners: Int?
    public let startTime: Date?
    public let requester: Requester?

    public struct Requester: Decodable, Sendable {
        public let name: String
    }

    private enum CodingKeys: String, CodingKey {
        case song, lastPlayed, listeners, startTime, requester
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        song = try values.decode(Track.self, forKey: .song)
        lastPlayed = try values.decodeIfPresent([Track].self, forKey: .lastPlayed) ?? []
        listeners = try values.decodeIfPresent(Int.self, forKey: .listeners)
        requester = try values.decodeIfPresent(Requester.self, forKey: .requester)
        if let timestamp = try values.decodeIfPresent(String.self, forKey: .startTime) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            startTime = formatter.date(from: timestamp)
                ?? ISO8601DateFormatter().date(from: timestamp)
        } else {
            startTime = nil
        }
    }
}

public enum GatewayMessage: Decodable, Sendable {
    case hello(heartbeatInterval: TimeInterval)
    case trackUpdate(TrackUpdate)
    case heartbeatAcknowledged
    case ignored

    private enum CodingKeys: String, CodingKey { case op, d, t }
    private struct Hello: Decodable { let heartbeat: Double }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Int.self, forKey: .op) {
        case 0:
            let hello = try values.decode(Hello.self, forKey: .d)
            guard hello.heartbeat.isFinite, (1_000...120_000).contains(hello.heartbeat) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .d, in: values, debugDescription: "Invalid heartbeat interval"
                )
            }
            self = .hello(heartbeatInterval: hello.heartbeat / 1_000)
        case 1:
            let event = try values.decodeIfPresent(String.self, forKey: .t)
            if event == "TRACK_UPDATE" || event == "TRACK_UPDATE_REQUEST" {
                self = .trackUpdate(try values.decode(TrackUpdate.self, forKey: .d))
            } else {
                self = .ignored
            }
        case 10:
            self = .heartbeatAcknowledged
        default:
            self = .ignored
        }
    }
}
