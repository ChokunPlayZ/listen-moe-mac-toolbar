import Foundation
import Testing
import RadioCore

struct DiscordRPCProtocolTests {
    @Test func validatesApplicationIDsWithoutAcceptingSecretsOrUnicodeDigits() {
        #expect(DiscordRPCProtocol.isValidApplicationID("123456789012345678"))
        #expect(!DiscordRPCProtocol.isValidApplicationID(""))
        #expect(!DiscordRPCProtocol.isValidApplicationID("not-an-id"))
        #expect(!DiscordRPCProtocol.isValidApplicationID("１２３４５６７８９０１２３４５６７８"))
    }

    @Test func handshakeUsesVersionOneAndApplicationID() throws {
        var buffer = try DiscordRPCProtocol.handshake(applicationID: "123456789012345678")
        let frame = try #require(DiscordRPCProtocol.decode(buffer: &buffer).first)
        #expect(frame.opcode == 0)
        let object = try #require(JSONSerialization.jsonObject(with: frame.payload) as? [String: Any])
        #expect(object["v"] as? Int == 1)
        #expect(object["client_id"] as? String == "123456789012345678")
        #expect(buffer.isEmpty)
    }

    @Test func handlesFragmentedAndCombinedPackets() throws {
        let packet = DiscordRPCProtocol.encode(opcode: .ping, payload: Data("ping".utf8))
        var buffer = Data(packet.prefix(6))
        #expect(try DiscordRPCProtocol.decode(buffer: &buffer).isEmpty)
        buffer.append(packet.dropFirst(6))
        buffer.append(DiscordRPCProtocol.encode(opcode: .frame, payload: Data("{}".utf8)))
        let frames = try DiscordRPCProtocol.decode(buffer: &buffer)
        #expect(frames.count == 2)
        #expect(frames.first?.opcode == 3)
        #expect(frames.first?.payload == Data("ping".utf8))
        #expect(buffer.isEmpty)
    }

    @Test func rejectsOversizedFrames() {
        var buffer = Data([1, 0, 0, 0, 255, 255, 255, 127])
        #expect(throws: DiscordRPCProtocol.ProtocolError.self) { try DiscordRPCProtocol.decode(buffer: &buffer) }
    }

    @Test func activityIncludesMetadataAndCanBeCleared() throws {
        let track = try JSONDecoder().decode(Track.self, from: Data(#"{"id":1,"title":"Song","artists":[{"id":1,"name":"Artist"}],"duration":120}"#.utf8))
        let now = Date(timeIntervalSince1970: 1_000)
        let activity = DiscordActivity(track: track, station: .jpop, romanized: true, startedAt: now.addingTimeInterval(-30), origin: "Anime: Test", now: now)
        #expect(activity.details == "Song")
        #expect(activity.state == "Artist · J-pop")
        #expect(activity.timestamps?.start == 970)
        #expect(activity.timestamps?.end == 1_090)
        #expect(activity.assets?.large_text == "Anime: Test")
        var buffer = try DiscordRPCProtocol.activity(activity, processID: 42, nonce: "test")
        let frame = try #require(DiscordRPCProtocol.decode(buffer: &buffer).first)
        let json = try #require(JSONSerialization.jsonObject(with: frame.payload) as? [String: Any])
        #expect(json["cmd"] as? String == "SET_ACTIVITY")
        let args = try #require(json["args"] as? [String: Any])
        #expect(args["pid"] as? Int == 42)
        #expect((args["activity"] as? [String: Any])?["type"] as? Int == 2)
        buffer = try DiscordRPCProtocol.activity(nil, processID: 42)
        let clear = try #require(DiscordRPCProtocol.decode(buffer: &buffer).first)
        let clearJSON = try #require(JSONSerialization.jsonObject(with: clear.payload) as? [String: Any])
        #expect((clearJSON["args"] as? [String: Any])?["activity"] is NSNull)
    }
}
