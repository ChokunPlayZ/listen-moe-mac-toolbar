import Foundation

@MainActor
protocol RadioGatewaySocket: AnyObject {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func receive() async throws -> URLSessionWebSocketTask.Message
    func send(_ message: URLSessionWebSocketTask.Message) async throws
}

extension URLSessionWebSocketTask: RadioGatewaySocket {}

@MainActor
public final class RadioGateway {
    public enum State: Equatable, Sendable {
        case disconnected, connecting, connected, reconnecting
    }

    public var onUpdate: ((TrackUpdate) -> Void)?
    public var onStateChange: ((State) -> Void)?

    private let makeSocket: (Station) -> any RadioGatewaySocket
    private let sleep: (TimeInterval) async throws -> Void
    private let now: () -> Date
    private var connectionTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var metadataTimeout: Task<Void, Never>?
    private var socket: (any RadioGatewaySocket)?
    private var generation = UUID()
    private var awaitingHeartbeat = false

    public convenience init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        self.init(makeSocket: { session.webSocketTask(with: $0.gatewayURL) })
    }

    init(
        makeSocket: @escaping (Station) -> any RadioGatewaySocket,
        sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping () -> Date = { .now }
    ) {
        self.makeSocket = makeSocket
        self.sleep = sleep
        self.now = now
    }

    public func connect(to station: Station) {
        disconnect()
        let generation = UUID()
        self.generation = generation
        connectionTask = Task { [weak self] in
            await self?.run(station: station, generation: generation)
        }
    }

    public func disconnect() {
        generation = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        metadataTimeout?.cancel()
        metadataTimeout = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        awaitingHeartbeat = false
        onStateChange?(.disconnected)
    }

    private func run(station: Station, generation: UUID) async {
        var failures = 0
        while !Task.isCancelled, self.generation == generation {
            onStateChange?(failures == 0 ? .connecting : .reconnecting)
            guard !Task.isCancelled, self.generation == generation else { return }
            let socket = makeSocket(station)
            self.socket = socket
            awaitingHeartbeat = false
            var receivedHello = false
            var announcedConnection = false
            let connectedAt = now()
            socket.resume()
            // A welcome/heartbeat alone does not mean we have usable song info.
            armMetadataTimeout(socket: socket, delay: 25, generation: generation)

            do {
                while !Task.isCancelled, self.generation == generation {
                    let frame = try await socket.receive()
                    guard !Task.isCancelled, self.generation == generation, self.socket === socket else { return }
                    let data: Data
                    switch frame {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    guard let message = try? JSONDecoder().decode(GatewayMessage.self, from: data) else {
                        continue
                    }
                    switch message {
                    case .hello(let interval):
                        receivedHello = true
                        startHeartbeat(socket: socket, interval: interval, generation: generation)
                    case .trackUpdate(let update):
                        guard receivedHello else { continue }
                        // Don't publish a long-expired snapshot queued before sleep.
                        if let end = update.startTime, now().timeIntervalSince(end) > 15 { continue }
                        onUpdate?(update)
                        guard !Task.isCancelled, self.generation == generation, self.socket === socket else { return }
                        let remaining = update.startTime?.timeIntervalSince(now())
                            ?? (update.song.duration > 0 ? update.song.duration : 300)
                        armMetadataTimeout(socket: socket, delay: max(1, remaining + 15), generation: generation)
                        if !announcedConnection {
                            announcedConnection = true
                            onStateChange?(.connected)
                        }
                    case .heartbeatAcknowledged:
                        awaitingHeartbeat = false
                    case .ignored:
                        break
                    }
                }
            } catch {
                // Network failures, missed heartbeats and stale metadata reconnect below.
            }

            guard !Task.isCancelled, self.generation == generation else { return }
            heartbeatTask?.cancel()
            metadataTimeout?.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            self.socket = nil
            if now().timeIntervalSince(connectedAt) > 60 { failures = 0 }
            failures = min(failures + 1, 6)
            onStateChange?(.reconnecting)
            let delay = min(pow(2, Double(failures - 1)), 30) + Double.random(in: 0...0.5)
            do { try await sleep(delay) } catch { return }
        }
    }

    private func armMetadataTimeout(socket: any RadioGatewaySocket, delay: TimeInterval, generation: UUID) {
        metadataTimeout?.cancel()
        metadataTimeout = Task { [weak self, sleep] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self,
                  self.generation == generation, self.socket === socket else { return }
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private func startHeartbeat(socket: any RadioGatewaySocket, interval: TimeInterval, generation: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, sleep] in
            do {
                while !Task.isCancelled {
                    guard let self, self.generation == generation, self.socket === socket else { return }
                    guard !self.awaitingHeartbeat else {
                        socket.cancel(with: .goingAway, reason: nil)
                        return
                    }
                    self.awaitingHeartbeat = true
                    try await socket.send(.string("{\"op\":9}"))
                    try await sleep(interval)
                }
            } catch {
                guard !Task.isCancelled, let self,
                      self.generation == generation, self.socket === socket else { return }
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}
