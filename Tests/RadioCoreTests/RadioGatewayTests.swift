import Foundation
import Testing
@testable import RadioCore

@MainActor
struct RadioGatewayTests {
    @Test func welcomeAndHeartbeatsWithoutSongInfoTriggerReconnect() async throws {
        let clock = GatewayTestClock()
        let first = GatewayTestSocket()
        let second = GatewayTestSocket()
        var sockets = [first, second]
        let gateway = RadioGateway(makeSocket: { _ in sockets.removeFirst() }, sleep: clock.sleep, now: { clock.now })
        var states: [RadioGateway.State] = []
        var updates: [TrackUpdate] = []
        gateway.onStateChange = { states.append($0) }
        gateway.onUpdate = { updates.append($0) }
        defer { gateway.disconnect() }

        gateway.connect(to: .jpop)
        first.push(hello)
        // This used to cancel the welcome watchdog, leaving the old song forever.
        first.push(#"{"op":1,"t":"TRACK_UPDATE","d":{"song":{"id":1}}}"#)
        await eventually { first.sent.count == 1 && clock.hasSleep(25) }
        #expect(!states.contains(.connected))
        #expect(updates.isEmpty)

        clock.advance(by: 25)
        await eventually { first.isCancelled && clock.hasRetry }
        #expect(states.last == .reconnecting)
        clock.advance(by: 2)
        await eventually { second.isResumed }
        second.push(hello)
        second.push(try snapshot(id: 2, end: clock.now.addingTimeInterval(90)))
        await eventually { updates.count == 1 && states.last == .connected }
        #expect(updates.first?.song.id == 2)
    }

    @Test func reconnectRefreshesCurrentSongWithoutWaitingForNextSong() async throws {
        let clock = GatewayTestClock()
        let first = GatewayTestSocket()
        let second = GatewayTestSocket()
        var sockets = [first, second]
        let gateway = RadioGateway(makeSocket: { _ in sockets.removeFirst() }, sleep: clock.sleep, now: { clock.now })
        var updates: [TrackUpdate] = []
        gateway.onUpdate = { updates.append($0) }
        defer { gateway.disconnect() }
        let end = clock.now.addingTimeInterval(90)
        let current = try snapshot(id: 42, end: end)

        gateway.connect(to: .jpop)
        first.push(hello)
        first.push(current)
        await eventually { updates.count == 1 }
        gateway.disconnect() // System sleep.
        clock.advance(by: 30)
        gateway.connect(to: .jpop)
        second.push(hello)
        second.push(current) // Same song, not a song-change event.
        await eventually { updates.count == 2 }

        #expect(first.isCancelled)
        #expect(updates.map(\.song.id) == [42, 42])
        #expect(updates[0].startedAt == updates[1].startedAt)
        #expect(updates[1].requester?.name == "A Listener")
    }

    @Test func heartbeatsCannotKeepExpiredSongInfoConnected() async throws {
        let clock = GatewayTestClock()
        let first = GatewayTestSocket()
        let second = GatewayTestSocket()
        var sockets = [first, second]
        let gateway = RadioGateway(makeSocket: { _ in sockets.removeFirst() }, sleep: clock.sleep, now: { clock.now })
        var updates: [TrackUpdate] = []
        gateway.onUpdate = { updates.append($0) }
        defer { gateway.disconnect() }

        gateway.connect(to: .jpop)
        first.push(hello)
        first.push(try snapshot(id: 1, end: clock.now.addingTimeInterval(5)))
        await eventually { updates.count == 1 && clock.hasSleep(20) }
        // Even repeated snapshots of the same song cannot extend its broadcast end.
        clock.advance(by: 10)
        first.push(try snapshot(id: 1, end: clock.now.addingTimeInterval(-5)))
        await eventually { updates.count == 2 && clock.hasSleep(10) }
        clock.advance(by: 11)
        await eventually { first.isCancelled && clock.hasRetry }
        clock.advance(by: 2)
        await eventually { second.isResumed }
        second.push(hello)
        second.push(try snapshot(id: 2, end: clock.now.addingTimeInterval(90)))
        await eventually { updates.count == 3 }
        #expect(updates.last?.song.id == 2)
    }

    @Test func newSongCancelsOldMetadataDeadline() async throws {
        let clock = GatewayTestClock()
        let socket = GatewayTestSocket()
        let gateway = RadioGateway(makeSocket: { _ in socket }, sleep: clock.sleep, now: { clock.now })
        var updates: [TrackUpdate] = []
        gateway.onUpdate = { updates.append($0) }
        defer { gateway.disconnect() }

        gateway.connect(to: .jpop)
        socket.push(hello)
        socket.push(try snapshot(id: 1, end: clock.now.addingTimeInterval(5)))
        await eventually { clock.hasSleep(20) }
        socket.push(try snapshot(id: 2, end: clock.now.addingTimeInterval(120)))
        await eventually { updates.count == 2 && clock.hasSleep(135) }
        clock.advance(by: 21)
        await eventually { !clock.hasSleep(20) }
        #expect(!socket.isCancelled)
        #expect(updates.last?.song.id == 2)
    }

    @Test func oldSocketCannotPublishAfterWakeOrStationSwitch() async throws {
        let clock = GatewayTestClock()
        let old = GatewayTestSocket()
        old.delaysCancellation = true
        let current = GatewayTestSocket()
        var sockets = [old, current]
        var stations: [Station] = []
        let gateway = RadioGateway(makeSocket: {
            stations.append($0)
            return sockets.removeFirst()
        }, sleep: clock.sleep, now: { clock.now })
        var updates: [TrackUpdate] = []
        gateway.onUpdate = { updates.append($0) }
        defer { gateway.disconnect() }

        gateway.connect(to: .jpop)
        old.push(hello)
        await eventually { old.sent.count == 1 && old.isReceiving }
        gateway.connect(to: .kpop)
        current.push(hello)
        current.push(try snapshot(id: 2, end: clock.now.addingTimeInterval(90)))
        await eventually { updates.count == 1 }
        old.push(try snapshot(id: 1, end: clock.now.addingTimeInterval(90)))
        await eventually { !old.isReceiving }
        #expect(updates.map(\.song.id) == [2])
        #expect(stations == [.jpop, .kpop])
        #expect(!current.isCancelled)
    }

    @Test func expiredSnapshotDoesNotMasqueradeAsCurrentSong() async throws {
        let clock = GatewayTestClock()
        let socket = GatewayTestSocket()
        let gateway = RadioGateway(makeSocket: { _ in socket }, sleep: clock.sleep, now: { clock.now })
        var states: [RadioGateway.State] = []
        var updates: [TrackUpdate] = []
        gateway.onStateChange = { states.append($0) }
        gateway.onUpdate = { updates.append($0) }
        defer { gateway.disconnect() }

        gateway.connect(to: .jpop)
        socket.push(hello)
        socket.push(try snapshot(id: 1, end: clock.now.addingTimeInterval(-60)))
        await eventually { socket.sent.count == 1 && socket.isReceiving }
        #expect(updates.isEmpty)
        #expect(!states.contains(.connected))
        #expect(clock.hasSleep(25))
    }

    private let hello = #"{"op":0,"d":{"heartbeat":35000}}"#

    private func snapshot(id: Int, end: Date) throws -> String {
        let payload: [String: Any] = [
            "op": 1, "t": "TRACK_UPDATE", "d": [
                "song": ["id": id, "title": "Current song", "duration": 120],
                "startTime": ISO8601DateFormatter().string(from: end),
                "requester": ["username": "listener", "displayName": "A Listener"],
            ],
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
    }

    private func eventually(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Gateway did not reach the expected state", sourceLocation: sourceLocation)
    }
}

@MainActor
private final class GatewayTestSocket: RadioGatewaySocket {
    private var frames: [URLSessionWebSocketTask.Message] = []
    private var receiver: CheckedContinuation<URLSessionWebSocketTask.Message, any Error>?
    private(set) var sent: [URLSessionWebSocketTask.Message] = []
    private(set) var isResumed = false
    private(set) var isCancelled = false
    var delaysCancellation = false
    var isReceiving: Bool { receiver != nil }

    func resume() { isResumed = true }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isCancelled = true
        guard !delaysCancellation else { return }
        let pending = receiver
        receiver = nil
        pending?.resume(throwing: CancellationError())
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        if isCancelled { throw CancellationError() }
        if !frames.isEmpty { return frames.removeFirst() }
        return try await withCheckedThrowingContinuation { receiver = $0 }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        if isCancelled { throw CancellationError() }
        sent.append(message)
        push(#"{"op":10}"#)
    }

    func push(_ text: String) {
        if let pending = receiver {
            receiver = nil
            pending.resume(returning: .string(text))
        } else {
            frames.append(.string(text))
        }
    }
}

@MainActor
private final class GatewayTestClock {
    private struct Waiter {
        let interval: TimeInterval
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var waiters: [UUID: Waiter] = [:]
    private(set) var now = Date(timeIntervalSince1970: 1_000)

    func sleep(_ interval: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = Waiter(interval: interval, deadline: now.addingTimeInterval(interval), continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in
                self.waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
            }
        }
    }

    func hasSleep(_ interval: TimeInterval) -> Bool { waiters.values.contains { $0.interval == interval } }
    var hasRetry: Bool { waiters.values.contains { (1...1.5).contains($0.interval) } }

    func advance(by interval: TimeInterval) {
        now.addTimeInterval(interval)
        let due = waiters.filter { $0.value.deadline <= now }
        for (id, waiter) in due {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }
}
