import Foundation
import Testing
import RadioCore

struct LiveGatewayTests {
    enum ProbeError: Error { case timeout, closed }

    @MainActor
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["LISTEN_MOE_LIVE_TESTS"] == "1"),
        arguments: Station.allCases
    )
    func appGatewayRefreshesImmediatelyAfterReconnect(station: Station) async throws {
        let gateway = RadioGateway()
        let (events, continuation) = AsyncStream.makeStream(of: TrackUpdate.self)
        gateway.onUpdate = { continuation.yield($0) }
        defer {
            gateway.disconnect()
            continuation.finish()
        }
        gateway.connect(to: station)
        let first = try await nextSnapshot(in: events)
        gateway.disconnect()
        gateway.connect(to: station)
        let refreshed = try await nextSnapshot(in: events)
        #expect(!refreshed.song.title.isEmpty)
        #expect(try #require(refreshed.startTime).timeIntervalSinceNow >= -15)
        if first.song.id == refreshed.song.id {
            #expect(first.startedAt == refreshed.startedAt)
        }
    }

    private func nextSnapshot(in events: AsyncStream<TrackUpdate>) async throws -> TrackUpdate {
        try await withThrowingTaskGroup(of: TrackUpdate.self) { group in
            group.addTask {
                for await update in events { return update }
                throw ProbeError.closed
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw ProbeError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    // Opt in explicitly: normal tests are deterministic and work without a network.
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["LISTEN_MOE_LIVE_TESTS"] == "1"),
        arguments: Station.allCases
    )
    func receivesTrackAndHeartbeat(station: Station) async throws {
        let socket = URLSession.shared.webSocketTask(with: station.gatewayURL)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        let update = try await withThrowingTaskGroup(of: TrackUpdate.self) { group in
            group.addTask {
                var trackUpdate: TrackUpdate?
                var acknowledged = false
                while !Task.isCancelled {
                    let frame = try await socket.receive()
                    let data: Data
                    switch frame {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    switch try JSONDecoder().decode(GatewayMessage.self, from: data) {
                    case .hello:
                        try await socket.send(.string("{\"op\":9}"))
                    case .trackUpdate(let update):
                        trackUpdate = update
                    case .heartbeatAcknowledged:
                        acknowledged = true
                    case .ignored:
                        break
                    }
                    if let trackUpdate, acknowledged { return trackUpdate }
                }
                throw ProbeError.closed
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                socket.cancel(with: .goingAway, reason: nil)
                throw ProbeError.timeout
            }
            defer {
                group.cancelAll()
                socket.cancel(with: .normalClosure, reason: nil)
            }
            return try await group.next()!
        }
        #expect(!update.song.title.isEmpty)
        #expect(update.song.id > 0)
        let start = try #require(update.startedAt)
        let end = try #require(update.startTime)
        let now = Date.now
        #expect(abs(end.timeIntervalSince(start) - update.song.duration) < 0.001)
        // Allow a little metadata/heartbeat latency at a song boundary.
        #expect(start.timeIntervalSince(now) <= 10)
        #expect(end.timeIntervalSince(now) >= -10)
    }
}
