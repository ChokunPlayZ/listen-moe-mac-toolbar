import Darwin
import Foundation
import RadioCore

/// Talks only to the user's local Discord desktop IPC socket. No token or SDK.
@MainActor
final class DiscordPresence {
    enum State: Equatable {
        case disabled, needsApplicationID, waitingForDiscord, connecting, connected
        case failed(String)

        var description: String {
            switch self {
            case .disabled: "Discord sharing is off."
            case .needsApplicationID: "Enter a valid Discord application ID to connect."
            case .waitingForDiscord: "Waiting for the Discord desktop app…"
            case .connecting: "Connecting to Discord…"
            case .connected: "Connected to Discord. Songs are shared only while playing."
            case .failed(let message): "Discord: \(message)"
            }
        }
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .disabled {
        didSet { if oldValue != state { onStateChange?(state) } }
    }
    private var enabled = false
    private var applicationID = ""
    private var activity: DiscordActivity?
    private var descriptor: Int32 = -1
    private var generation = UUID()
    private var ready = false
    private var incoming = Data()
    private var outgoing = Data()
    private var readSource: (any DispatchSourceRead)?
    private var writeSource: (any DispatchSourceWrite)?
    private var retryTask: Task<Void, Never>?
    private var welcomeTimeout: Task<Void, Never>?

    func configure(enabled: Bool, applicationID: String) {
        guard self.enabled != enabled || self.applicationID != applicationID else { return }
        disconnect(clearActivity: true)
        self.enabled = enabled
        self.applicationID = applicationID
        guard enabled else { state = .disabled; return }
        guard DiscordRPCProtocol.isValidApplicationID(applicationID) else { state = .needsApplicationID; return }
        connect()
    }

    func update(_ activity: DiscordActivity?) {
        guard self.activity != activity else { return }
        self.activity = activity
        publishActivity()
    }

    func shutdown() {
        enabled = false
        disconnect(clearActivity: true)
        state = .disabled
    }

    private func connect() {
        guard enabled, DiscordRPCProtocol.isValidApplicationID(applicationID) else { return }
        for path in Self.socketPaths() {
            guard let fd = Self.openSocket(path: path) else { continue }
            descriptor = fd
            generation = UUID()
            let generation = generation
            ready = false
            state = .connecting
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.readAvailable()
                }
            }
            readSource = source
            source.setCancelHandler { Darwin.close(fd) }
            source.resume()
            if let handshake = try? DiscordRPCProtocol.handshake(applicationID: applicationID) { send(handshake) }
            guard descriptor == fd else { return }
            welcomeTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                guard let self, self.generation == generation, !self.ready else { return }
                self.connectionLost()
            }
            return
        }
        state = .waitingForDiscord
        scheduleRetry()
    }

    private func readAvailable() {
        guard descriptor >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.recv(descriptor, &bytes, bytes.count, 0)
            if count > 0 {
                incoming.append(contentsOf: bytes.prefix(count))
                do {
                    for frame in try DiscordRPCProtocol.decode(buffer: &incoming) {
                        receive(frame)
                        if descriptor < 0 { return }
                    }
                } catch {
                    connectionLost(message: "Invalid IPC packet.")
                    return
                }
            } else if count == 0 {
                connectionLost()
                return
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                connectionLost()
                return
            }
        }
    }

    private func receive(_ frame: DiscordRPCProtocol.Frame) {
        switch frame.opcode {
        case DiscordRPCProtocol.Opcode.ping.rawValue:
            send(DiscordRPCProtocol.encode(opcode: .pong, payload: frame.payload))
        case DiscordRPCProtocol.Opcode.close.rawValue:
            connectionLost(message: "Connection closed. Check the application ID.")
        case DiscordRPCProtocol.Opcode.frame.rawValue:
            guard let json = try? JSONSerialization.jsonObject(with: frame.payload) as? [String: Any] else { return }
            if json["evt"] as? String == "READY" {
                ready = true
                welcomeTimeout?.cancel()
                state = .connected
                publishActivity()
            } else if json["evt"] as? String == "ERROR" {
                let message = (json["data"] as? [String: Any])?["message"] as? String ?? "Activity was rejected."
                state = .failed(message)
            } else if json["cmd"] as? String == "SET_ACTIVITY" {
                state = .connected
            }
        default:
            break
        }
    }

    private func publishActivity() {
        guard ready, let packet = try? DiscordRPCProtocol.activity(activity, processID: getpid()) else { return }
        send(packet)
    }

    private func send(_ packet: Data) {
        guard descriptor >= 0 else { return }
        outgoing.append(packet)
        guard outgoing.count <= 262_144 else { connectionLost(); return }
        flushWrites()
    }

    private func flushWrites() {
        while descriptor >= 0, !outgoing.isEmpty {
            let count = outgoing.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
            if count > 0 {
                outgoing = Data(outgoing.dropFirst(count))
            } else if count < 0, errno == EINTR {
                continue
            } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                if writeSource == nil {
                    let generation = generation
                    let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: .main)
                    source.setEventHandler { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == generation else { return }
                            self.flushWrites()
                        }
                    }
                    writeSource = source
                    source.resume()
                }
                return
            } else {
                connectionLost()
                return
            }
        }
        writeSource?.cancel()
        writeSource = nil
    }

    private func connectionLost(message: String? = nil) {
        disconnect(clearActivity: false)
        state = message.map(State.failed) ?? .waitingForDiscord
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard enabled, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self else { return }
            self.retryTask = nil
            self.connect()
        }
    }

    private func disconnect(clearActivity: Bool) {
        if clearActivity, ready, let packet = try? DiscordRPCProtocol.activity(nil, processID: getpid()) {
            send(packet)
        }
        generation = UUID()
        retryTask?.cancel()
        retryTask = nil
        welcomeTimeout?.cancel()
        welcomeTimeout = nil
        writeSource?.cancel()
        writeSource = nil
        if descriptor >= 0 { Darwin.shutdown(descriptor, SHUT_RDWR) }
        // Keep the descriptor reserved until its dispatch source has stopped.
        if let readSource {
            readSource.cancel()
        } else if descriptor >= 0 {
            Darwin.close(descriptor)
        }
        readSource = nil
        descriptor = -1
        ready = false
        incoming = Data()
        outgoing = Data()
    }

    private static func socketPaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let directories = [environment["XDG_RUNTIME_DIR"], environment["TMPDIR"], environment["TMP"], environment["TEMP"], NSTemporaryDirectory(), "/tmp", "/var/tmp"].compactMap { $0 }
        var seen = Set<String>()
        return directories.flatMap { directory in
            (0..<10).map { URL(fileURLWithPath: directory).appendingPathComponent("discord-ipc-\($0)").path }
        }.filter { seen.insert($0).inserted }
    }

    private static func openSocket(path: String) -> Int32? {
        var address = sockaddr_un()
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else { return nil }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else { Darwin.close(fd); return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.copyBytes(from: path.utf8)
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { Darwin.close(fd); return nil }
        return fd
    }
}
