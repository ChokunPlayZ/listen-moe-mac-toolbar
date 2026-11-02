import Foundation

public struct DiscordActivity: Encodable, Equatable, Sendable {
    public let type = 2 // Listening
    public let details: String
    public let state: String
    public let timestamps: Timestamps?
    public let assets: Assets?
    public let buttons = [Button(label: "Listen live", url: "https://listen.moe")]

    public struct Timestamps: Encodable, Equatable, Sendable {
        public let start: Int
        public let end: Int?
    }
    public struct Assets: Encodable, Equatable, Sendable {
        public let large_image: String?
        public let large_text: String
    }
    public struct Button: Encodable, Equatable, Sendable {
        public let label: String
        public let url: String
    }

    public init(track: Track?, station: Station, romanized: Bool, startedAt: Date?, origin: String?, now: Date = .now) {
        details = String((track?.displayTitle(romanized: romanized) ?? "LISTEN.moe live radio").prefix(128))
        state = String("\(track?.artistName(romanized: romanized) ?? "LISTEN.moe") · \(station.name)".prefix(128))
        if let startedAt, startedAt <= now,
           let duration = track?.duration, duration > 0,
           startedAt.addingTimeInterval(duration) > now {
            timestamps = Timestamps(start: Int(startedAt.timeIntervalSince1970), end: Int(startedAt.timeIntervalSince1970 + duration))
        } else {
            timestamps = nil
        }
        assets = Assets(
            large_image: track?.artworkURL?.absoluteString,
            large_text: String((origin ?? track?.albumName(romanized: romanized) ?? "LISTEN.moe · \(station.name)").prefix(128))
        )
    }
}

public enum DiscordRPCProtocol {
    public enum Opcode: UInt32, Sendable { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }
    public struct Frame: Sendable {
        public let opcode: UInt32
        public let payload: Data
    }
    public enum ProtocolError: Error { case oversizedFrame }

    public static func isValidApplicationID(_ value: String) -> Bool {
        (17...22).contains(value.count) && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    public static func encode(opcode: Opcode, payload: Data) -> Data {
        var code = opcode.rawValue.littleEndian
        var length = UInt32(payload.count).littleEndian
        var packet = Data()
        withUnsafeBytes(of: &code) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }

    /// Keeps incomplete packets buffered; rejects unbounded data from an IPC peer.
    public static func decode(buffer: inout Data) throws -> [Frame] {
        var frames: [Frame] = []
        while buffer.count >= 8 {
            let header = buffer.prefix(8)
            let opcode = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
            let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
            guard length <= 65_536 else { throw ProtocolError.oversizedFrame }
            guard buffer.count >= 8 + Int(length) else { break }
            frames.append(Frame(opcode: opcode, payload: Data(buffer.dropFirst(8).prefix(Int(length)))))
            buffer = Data(buffer.dropFirst(8 + Int(length)))
        }
        return frames
    }

    public static func handshake(applicationID: String) throws -> Data {
        encode(opcode: .handshake, payload: try JSONSerialization.data(withJSONObject: ["v": 1, "client_id": applicationID]))
    }

    public static func activity(_ activity: DiscordActivity?, processID: Int32, nonce: String = UUID().uuidString) throws -> Data {
        let object: Any
        if let activity {
            object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(activity))
        } else {
            object = NSNull()
        }
        let payload = try JSONSerialization.data(withJSONObject: [
            "cmd": "SET_ACTIVITY", "args": ["pid": processID, "activity": object], "nonce": nonce,
        ])
        return encode(opcode: .frame, payload: payload)
    }
}
