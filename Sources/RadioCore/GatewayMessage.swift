import Foundation

public struct TrackUpdate: Decodable, Sendable {
    public let song: Track
    public let lastPlayed: [Track]
    public let listeners: Int?
    // Despite the API field name, this is the scheduled end of the current song.
    public let startTime: Date?
    public let requester: Requester?

    public var startedAt: Date? {
        guard let startTime, song.duration.isFinite, song.duration > 0 else { return nil }
        // Match the official web client's broadcast clock: startTime - duration.
        return startTime.addingTimeInterval(-song.duration)
    }

    public struct Requester: Decodable, Sendable {
        public let name: String

        private enum CodingKeys: String, CodingKey { case name, username, displayName }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            // Current gateways use displayName/username; older payloads use name.
            name = (try? values.decode(String.self, forKey: .displayName))?.nonBlank
                ?? (try? values.decode(String.self, forKey: .username))?.nonBlank
                ?? (try? values.decode(String.self, forKey: .name))?.nonBlank
                ?? ""
        }
    }

    private enum CodingKeys: String, CodingKey {
        case song, lastPlayed, listeners, startTime, requester
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        song = try values.decode(Track.self, forKey: .song)
        // Auxiliary data must never prevent the current song from refreshing.
        var history: [Track] = []
        if var entries = try? values.nestedUnkeyedContainer(forKey: .lastPlayed) {
            while !entries.isAtEnd {
                let entry = try entries.superDecoder()
                if let track = try? Track(from: entry) { history.append(track) }
            }
        }
        lastPlayed = history
        listeners = try? values.decode(Int.self, forKey: .listeners)
        let decodedRequester = try? values.decode(Requester.self, forKey: .requester)
        requester = decodedRequester?.name.nonBlank == nil ? nil : decodedRequester
        if let timestamp = try? values.decode(String.self, forKey: .startTime) {
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
