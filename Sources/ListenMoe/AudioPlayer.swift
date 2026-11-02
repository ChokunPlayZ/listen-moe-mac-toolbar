import AVFoundation
import Foundation

@MainActor
final class AudioPlayer {
    enum State: Equatable, Sendable {
        case stopped, buffering, playing, reconnecting
        case failed(String)

        var isActive: Bool {
            switch self {
            case .buffering, .playing, .reconnecting: true
            case .stopped, .failed: false
            }
        }
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .stopped {
        didSet { if oldValue != state { onStateChange?(state) } }
    }
    var volume: Float = 0.65 {
        didSet { player.volume = min(max(volume, 0), 1) }
    }
    var isMuted = false {
        didSet { player.isMuted = isMuted }
    }

    private let player = AVPlayer()
    private var station: StationSelection?
    private var statusObservation: NSKeyValueObservation?
    private var timeObservation: NSKeyValueObservation?
    private var failedObserver: (any NSObjectProtocol)?
    private var stalledObserver: (any NSObjectProtocol)?
    private var endedObserver: (any NSObjectProtocol)?
    private var retryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()
    private var retryCount = 0

    // Keep the player independent of the metadata model.
    private struct StationSelection { let url: URL }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = volume
    }

    func play(url: URL) {
        stop()
        station = StationSelection(url: url)
        retryCount = 0
        load()
    }

    func stop() {
        generation = UUID()
        retryTask?.cancel()
        retryTask = nil
        clearItem()
        station = nil
        state = .stopped
    }

    private func clearItem() {
        timeoutTask?.cancel()
        timeoutTask = nil
        statusObservation?.invalidate()
        statusObservation = nil
        timeObservation?.invalidate()
        timeObservation = nil
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
        if let endedObserver { NotificationCenter.default.removeObserver(endedObserver) }
        failedObserver = nil
        stalledObserver = nil
        endedObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func load() {
        guard let station else { return }
        generation = UUID()
        let generation = generation
        clearItem()
        state = retryCount == 0 ? .buffering : .reconnecting
        let item = AVPlayerItem(url: station.url)
        item.preferredForwardBufferDuration = 2
        player.replaceCurrentItem(with: item)

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation, failed else { return }
                self.retry()
            }
        }
        timeObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation, self.station != nil else { return }
                if status == .playing {
                    self.timeoutTask?.cancel()
                    self.timeoutTask = nil
                    self.retryCount = 0
                    self.state = .playing
                } else {
                    self.state = self.retryCount == 0 ? .buffering : .reconnecting
                    self.armTimeout(generation: generation)
                }
            }
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.retry()
            }
        }
        endedObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            // A radio stream ending cleanly is still an interruption: rejoin live.
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.retry()
            }
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.state = .buffering
                self.armTimeout(generation: generation)
            }
        }
        armTimeout(generation: generation)
        player.play()
    }

    private func armTimeout(generation: UUID) {
        guard timeoutTask == nil else { return }
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.generation == generation, self.state != .playing else { return }
            self.retry()
        }
    }

    private func retry() {
        guard station != nil, retryTask == nil else { return }
        generation = UUID()
        clearItem()
        retryCount += 1
        guard retryCount <= 5 else {
            station = nil
            state = .failed("Couldn't reach the stream. Check your connection and try again.")
            return
        }
        state = .reconnecting
        let delay = min(pow(2, Double(retryCount - 1)), 15)
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.retryTask = nil
            self.load()
        }
    }
}
