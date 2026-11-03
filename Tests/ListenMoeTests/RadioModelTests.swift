import Foundation
import Testing
@testable import ListenMoe
@testable import RadioCore

@MainActor
struct RadioModelTests {
    @Test func sleepClearsStaleMetadataButPreservesSavedSongsAndSettings() throws {
        let fixture = RadioModelFixture()
        defer { fixture.finish() }
        let radio = fixture.radio
        fixture.gateway.onStateChange?(.connected)
        fixture.gateway.onUpdate?(try update())
        radio.volume = 0.25
        radio.toggleSave()
        let saved = radio.savedTracks
        #expect(radio.track != nil)
        #expect(!radio.recentTracks.isEmpty)
        #expect(!radio.origins.isEmpty)

        radio.prepareForSleep()

        #expect(radio.track == nil)
        #expect(radio.startedAt == nil)
        #expect(radio.listeners == nil)
        #expect(radio.requester == nil)
        #expect(radio.artwork == nil)
        #expect(radio.recentTracks.isEmpty)
        #expect(radio.origins.isEmpty)
        #expect(radio.originLookupState == .idle)
        #expect(radio.connectionState == .disconnected)
        #expect(radio.playbackState == .stopped)
        #expect(radio.savedTracks == saved)
        #expect(radio.volume == 0.25)
    }

    @Test func reconnectInvalidatesOldSongAndAcceptsSameSongSnapshot() throws {
        let fixture = RadioModelFixture()
        defer { fixture.finish() }
        let radio = fixture.radio
        let current = try update()
        fixture.gateway.onUpdate?(current)
        fixture.gateway.onStateChange?(.reconnecting)
        #expect(radio.track == nil)

        fixture.gateway.onUpdate?(current)
        fixture.gateway.onStateChange?(.connected)
        #expect(radio.track == current.song)
        #expect(radio.startedAt == current.startedAt)
        #expect(radio.requester == "A Listener")
        #expect(radio.origins.count == 1)
    }

    @Test func wakeRefreshesPausedRadioBeforeNextSong() async throws {
        let snapshot = try update()
        let fixture = RadioModelFixture(snapshot: snapshot)
        defer { fixture.finish() }
        let radio = fixture.radio
        fixture.gateway.onUpdate?(snapshot)
        radio.prepareForSleep()
        #expect(radio.track == nil)
        radio.resumeAfterSleep()

        for _ in 0..<2_000 {
            if radio.connectionState == .connected { break }
            await Task.yield()
        }
        #expect(radio.connectionState == .connected)
        #expect(radio.track == snapshot.song)
        #expect(radio.startedAt == snapshot.startedAt)
        #expect(radio.requester == "A Listener")
        #expect(radio.playbackState == .stopped)
    }

    private func update() throws -> TrackUpdate {
        try JSONDecoder().decode(TrackUpdate.self, from: Data("""
        {"song":{"id":42,"title":"Same current song","duration":120,
                 "sources":[{"id":3,"name":"Tagged source"}]},
         "startTime":"\(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(90)))",
         "lastPlayed":[{"id":41,"title":"Previous song"}],"listeners":100,
         "requester":{"username":"listener","displayName":"A Listener"}}
        """.utf8))
    }
}

@MainActor
private final class RadioModelFixture {
    let domain = "ListenMoeTests.RadioModel.\(UUID().uuidString)"
    let defaults: UserDefaults
    let gateway: RadioGateway
    let radio: RadioModel

    init(snapshot: TrackUpdate? = nil) {
        defaults = UserDefaults(suiteName: domain)!
        defaults.set(false, forKey: "autoDetectOrigins")
        gateway = RadioGateway(makeSocket: { _ in ModelTestSocket(snapshot: snapshot) })
        radio = RadioModel(defaults: defaults, gateway: gateway)
    }

    func finish() {
        gateway.disconnect()
        defaults.removePersistentDomain(forName: domain)
    }
}

@MainActor
private final class ModelTestSocket: RadioGatewaySocket {
    private let events: AsyncThrowingStream<URLSessionWebSocketTask.Message, any Error>
    private let continuation: AsyncThrowingStream<URLSessionWebSocketTask.Message, any Error>.Continuation

    init(snapshot: TrackUpdate?) {
        (events, continuation) = AsyncThrowingStream.makeStream()
        continuation.yield(.string(#"{"op":0,"d":{"heartbeat":35000}}"#))
        if let snapshot,
           let song = try? JSONEncoder().encode(snapshot.song),
           let end = snapshot.startTime {
            continuation.yield(.string("""
            {"op":1,"t":"TRACK_UPDATE","d":{
                "song":\(String(decoding: song, as: UTF8.self)),
                "startTime":"\(ISO8601DateFormatter().string(from: end))",
                "requester":{"username":"listener","displayName":"A Listener"}
            }}
            """))
        }
    }

    func resume() {}
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { continuation.finish() }
    func send(_ message: URLSessionWebSocketTask.Message) async throws { continuation.yield(.string(#"{"op":10}"#)) }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        var iterator = events.makeAsyncIterator()
        guard let frame = try await iterator.next() else { throw CancellationError() }
        return frame
    }
}
