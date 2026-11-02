import Foundation

@MainActor
public final class RadioGateway {
    public enum State: Equatable, Sendable {
        case disconnected, connecting, connected, reconnecting
    }

    public var onUpdate: ((TrackUpdate) -> Void)?
    public var onStateChange: ((State) -> Void)?

    private let session: URLSession
    private var connectionTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var welcomeTimeout: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var generation = UUID()
    private var awaitingHeartbeat = false

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
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
        welcomeTimeout?.cancel()
        welcomeTimeout = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        awaitingHeartbeat = false
        onStateChange?(.disconnected)
    }

    private func run(station: Station, generation: UUID) async {
        var failures = 0
        while !Task.isCancelled, self.generation == generation {
            onStateChange?(failures == 0 ? .connecting : .reconnecting)
            let socket = session.webSocketTask(with: station.gatewayURL)
            self.socket = socket
            awaitingHeartbeat = false
            let connectedAt = Date()
            socket.resume()
            welcomeTimeout = Task {
                do {
                    try await Task.sleep(for: .seconds(25))
                    socket.cancel(with: .goingAway, reason: nil)
                } catch { /* A welcome or disconnect cancels this watchdog. */ }
            }

            do {
                while !Task.isCancelled, self.generation == generation {
                    let frame = try await socket.receive()
                    guard self.generation == generation else { return }
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
                        welcomeTimeout?.cancel()
                        onStateChange?(.connected)
                        startHeartbeat(socket: socket, interval: interval, generation: generation)
                    case .trackUpdate(let update):
                        onUpdate?(update)
                    case .heartbeatAcknowledged:
                        awaitingHeartbeat = false
                    case .ignored:
                        break
                    }
                }
            } catch {
                // Both network failures and a missed heartbeat reconnect below.
            }

            guard !Task.isCancelled, self.generation == generation else { return }
            heartbeatTask?.cancel()
            welcomeTimeout?.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            self.socket = nil
            if Date().timeIntervalSince(connectedAt) > 60 { failures = 0 }
            failures = min(failures + 1, 6)
            onStateChange?(.reconnecting)
            let delay = min(pow(2, Double(failures - 1)), 30) + Double.random(in: 0...0.5)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
    }

    private func startHeartbeat(socket: URLSessionWebSocketTask, interval: TimeInterval, generation: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let self, self.generation == generation else { return }
                    guard !self.awaitingHeartbeat else {
                        socket.cancel(with: .goingAway, reason: nil)
                        return
                    }
                    self.awaitingHeartbeat = true
                    try await socket.send(.string("{\"op\":9}"))
                    try await Task.sleep(for: .seconds(interval))
                }
            } catch {
                guard !Task.isCancelled else { return }
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}
