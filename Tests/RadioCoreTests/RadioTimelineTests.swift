import Foundation
import Testing
@testable import RadioCore

struct RadioTimelineTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func derivesActualStartFromGatewayEndTime() throws {
        let metadata = try update(startTime: now.addingTimeInterval(90))
        #expect(metadata.startedAt == now.addingTimeInterval(-30))
        #expect(RadioTimeline.progress(since: metadata.startedAt, duration: 120, now: now) == 0.25)
        #expect(RadioTimeline.progress(
            since: metadata.startedAt, duration: 120, now: now.addingTimeInterval(30)
        ) == 0.5)
    }

    @Test func liveGatewayExampleMatchesWebsiteCalculation() throws {
        let metadata = try JSONDecoder().decode(TrackUpdate.self, from: Data("""
        {"song":{"id":23249,"title":"赤いリボン","duration":328},
         "startTime":"2026-11-02T18:57:07.801Z"}
        """.utf8))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedStart = try #require(formatter.date(from: "2026-11-02T18:51:39.801Z"))
        let receivedAt = try #require(formatter.date(from: "2026-11-02T18:52:53.000Z"))
        #expect(metadata.startedAt == expectedStart)
        let elapsed = RadioTimeline.elapsed(since: metadata.startedAt, duration: 328, now: receivedAt)
        #expect(abs(elapsed - 73.199) < 0.001)
        #expect(abs(RadioTimeline.progress(since: metadata.startedAt, duration: 328, now: receivedAt) - 73.199 / 328) < 0.00001)
    }

    @Test(arguments: [nil, "", "not-a-date"] as [String?])
    func unavailableTimestampDoesNotInventAStartTime(timestamp: String?) throws {
        let payload: [String: Any] = [
            "song": ["id": 1, "title": "Test", "duration": 120],
            "startTime": timestamp as Any? ?? NSNull(),
        ]
        let metadata = try JSONDecoder().decode(TrackUpdate.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(metadata.startedAt == nil)
    }

    @Test(arguments: [nil, 0, -1] as [Double?])
    func unavailableDurationDoesNotInventAStartTime(duration: Double?) throws {
        #expect(try update(startTime: now, duration: duration).startedAt == nil)
    }

    @Test func recalculatesStartWhenDurationIsCorrected() throws {
        let end = now.addingTimeInterval(90)
        #expect(try update(startTime: end, duration: 120).startedAt == now.addingTimeInterval(-30))
        #expect(try update(startTime: end, duration: 150).startedAt == now.addingTimeInterval(-60))
    }

    @Test func repeatedUpdatesAndReconnectingPreserveBroadcastPosition() throws {
        let end = now.addingTimeInterval(90)
        let first = try update(startTime: end)
        let reconnected = try update(startTime: end)
        #expect(first.startedAt == reconnected.startedAt)
        #expect(RadioTimeline.elapsed(
            since: reconnected.startedAt, duration: 120, now: now.addingTimeInterval(30)
        ) == 60)
    }

    @Test func discordUsesTheSameActualBroadcastStartAndEnd() throws {
        let end = now.addingTimeInterval(90)
        let metadata = try update(startTime: end)
        let activity = DiscordActivity(
            track: metadata.song, station: .jpop, romanized: false,
            startedAt: metadata.startedAt, origin: nil, now: now
        )
        #expect(activity.timestamps?.start == 970)
        #expect(activity.timestamps?.end == 1_090)
    }

    private func update(startTime: Date?, duration: Double? = 120) throws -> TrackUpdate {
        var song: [String: Any] = ["id": 1, "title": "Test"]
        if let duration { song["duration"] = duration }
        var payload: [String: Any] = ["song": song]
        if let startTime {
            payload["startTime"] = ISO8601DateFormatter().string(from: startTime)
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(TrackUpdate.self, from: data)
    }
}
