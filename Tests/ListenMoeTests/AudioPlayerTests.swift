import Foundation
import RadioCore
import Testing
@testable import ListenMoe

@MainActor
struct AudioPlayerTests {
    enum PlaybackError: Error { case timeout }

    @Test func initialStateAndStop() {
        let player = AudioPlayer()
        #expect(player.state == .stopped)
        #expect(!player.state.isActive)
        player.volume = 0.25
        player.isMuted = true
        player.stop()
        #expect(player.state == .stopped)
        #expect(player.volume == 0.25)
        #expect(player.isMuted)
    }

    @Test func pendingPlaybackCanBeCancelled() async {
        let player = AudioPlayer()
        player.isMuted = true
        player.play(url: URL(string: "https://127.0.0.1:1/not-a-stream")!)
        #expect(player.state.isActive)
        player.stop()
        await Task.yield()
        #expect(player.state == .stopped)
    }

    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["LISTEN_MOE_LIVE_TESTS"] == "1"),
        arguments: Station.allCases
    )
    func playsNativeStreamSilently(station: Station) async throws {
        let player = AudioPlayer()
        player.isMuted = true
        let (events, continuation) = AsyncStream.makeStream(of: AudioPlayer.State.self)
        player.onStateChange = { continuation.yield($0) }
        defer {
            player.stop()
            continuation.finish()
        }
        player.play(url: station.streamURL)

        let played = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await state in events {
                    if state == .playing { return true }
                    if case .failed = state { return false }
                }
                return false
            }
            group.addTask {
                try await Task.sleep(for: .seconds(25))
                throw PlaybackError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        #expect(played)
        player.stop()
        #expect(player.state == .stopped)
    }
}
