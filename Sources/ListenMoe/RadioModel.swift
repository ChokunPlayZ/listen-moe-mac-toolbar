import AppKit
import Combine
import MediaPlayer
import RadioCore
import ServiceManagement

@MainActor
final class RadioModel: ObservableObject {
    static let shared = RadioModel()

    @Published private(set) var station: Station
    @Published private(set) var track: Track?
    @Published private(set) var recentTracks: [Track] = []
    @Published private(set) var savedTracks: [SavedTrack]
    @Published private(set) var startedAt: Date?
    @Published private(set) var listeners: Int?
    @Published private(set) var requester: String?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var origins: [SongOrigin] = []
    @Published private(set) var originLookupState: OriginLookupState = .idle
    @Published private(set) var connectionState: RadioGateway.State = .connecting
    @Published private(set) var playbackState: AudioPlayer.State = .stopped
    @Published private(set) var launchAtLogin = false
    @Published var settingsError: String?
    @Published private(set) var discordState: DiscordPresence.State = .disabled
    @Published var discordEnabled: Bool {
        didSet {
            defaults.set(discordEnabled, forKey: "discordEnabled")
            configureDiscord()
        }
    }
    @Published var discordApplicationID: String {
        didSet {
            defaults.set(discordApplicationID, forKey: "discordApplicationID")
            configureDiscord()
        }
    }

    @Published var volume: Double {
        didSet {
            audio.volume = Float(volume)
            defaults.set(volume, forKey: "volume")
            if volume > 0, isMuted { isMuted = false }
        }
    }
    @Published var isMuted = false {
        didSet { audio.isMuted = isMuted }
    }
    @Published var autoplay: Bool {
        didSet { defaults.set(autoplay, forKey: "autoplay") }
    }
    @Published var showMenuBarTitle: Bool {
        didSet { defaults.set(showMenuBarTitle, forKey: "showMenuBarTitle") }
    }
    @Published var textDisplayMode: TextDisplayMode {
        didSet {
            defaults.set(textDisplayMode.rawValue, forKey: "textDisplayMode")
            updateNowPlaying()
            updateDiscordPresence()
        }
    }
    @Published var autoDetectOrigins: Bool {
        didSet {
            defaults.set(autoDetectOrigins, forKey: "autoDetectOrigins")
            if let track { loadOrigins(for: track) }
        }
    }

    enum OriginLookupState { case idle, searching, complete, unavailable }

    private let defaults: UserDefaults
    private let gateway: RadioGateway
    private let audio = AudioPlayer()
    private let discord = DiscordPresence()
    private let originResolver = SongOriginResolver()
    private var originTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?
    private var hasStarted = false
    private var isSleeping = false
    private var resumeOnWake = false
    private var workspaceObservers: [any NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    init(defaults: UserDefaults = .standard, gateway: RadioGateway = RadioGateway()) {
        self.defaults = defaults
        self.gateway = gateway
        station = Station(rawValue: defaults.string(forKey: "station") ?? "") ?? .jpop
        volume = defaults.object(forKey: "volume") as? Double ?? 0.65
        autoplay = defaults.bool(forKey: "autoplay")
        showMenuBarTitle = defaults.bool(forKey: "showMenuBarTitle")
        textDisplayMode = TextDisplayMode.load(from: defaults)
        autoDetectOrigins = defaults.object(forKey: "autoDetectOrigins") as? Bool ?? true
        discordEnabled = defaults.bool(forKey: "discordEnabled")
        discordApplicationID = defaults.string(forKey: "discordApplicationID") ?? ""
        if let data = defaults.data(forKey: "savedTracks"),
           let saved = try? JSONDecoder().decode([SavedTrack].self, from: data) {
            savedTracks = saved
        } else {
            savedTracks = []
        }
        defaults.set(textDisplayMode.rawValue, forKey: "textDisplayMode")
        audio.volume = Float(volume)
        audio.onStateChange = { [weak self] state in
            self?.playbackState = state
            self?.updateNowPlaying()
            self?.updateDiscordPresence()
        }
        discord.onStateChange = { [weak self] state in self?.discordState = state }
        gateway.onStateChange = { [weak self] state in
            guard let self else { return }
            self.connectionState = state
            if state != .connected { self.clearMetadata() }
        }
        gateway.onUpdate = { [weak self] update in self?.receive(update) }
    }

    var menuBarTooltip: String {
        guard let track else { return "LISTEN.moe · \(station.name) radio" }
        return "\(track.displayTitle(romanized: romanized)) — \(track.artistName(romanized: romanized))"
    }

    var isCurrentTrackSaved: Bool {
        guard let track else { return false }
        return savedTracks.contains { $0.station == station && $0.track.id == track.id }
    }

    var romanized: Bool { textDisplayMode == .romaji }
    var furigana: Bool { textDisplayMode == .furigana }

    var originSummary: String { originSummary(romanized: romanized) }

    func originSummary(romanized: Bool) -> String {
        if !origins.isEmpty {
            return origins.map { "\($0.kindLabel): \($0.displayName(romanized: romanized))" }.joined(separator: " · ")
        }
        switch originLookupState {
        case .searching: return "Identifying song origin…"
        case .unavailable: return "Source lookup unavailable"
        case .idle, .complete: return "No linked source found"
        }
    }

    var originAttribution: String {
        guard !origins.isEmpty else {
            return "Exact source tags or catalogue relationships are required. An unknown result does not mean this is an original song."
        }
        return origins.map(\.attribution).joined(separator: "\n")
    }

    var statusText: String {
        switch playbackState {
        case .playing: "Playing"
        case .buffering: "Connecting…"
        case .reconnecting: "Reconnecting to the stream…"
        case .failed(let message): message
        case .stopped: "Paused"
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        gateway.connect(to: station)
        refreshLoginStatus()
        configureRemoteCommands()
        configureDiscord()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForSleep() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAfterSleep() }
        })
        if autoplay { play() }
    }

    func prepareForSleep() {
        guard !isSleeping else { return }
        isSleeping = true
        resumeOnWake = playbackState.isActive
        audio.stop()
        gateway.disconnect()
    }

    func resumeAfterSleep() {
        guard isSleeping else { return }
        isSleeping = false
        gateway.connect(to: station)
        if resumeOnWake { play() }
        resumeOnWake = false
    }

    func shutdown() {
        audio.stop()
        gateway.disconnect()
        artworkTask?.cancel()
        originTask?.cancel()
        discord.shutdown()
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceObservers.removeAll()
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    func select(_ station: Station) {
        guard self.station != station else { return }
        let wasPlaying = playbackState.isActive
        audio.stop()
        self.station = station
        defaults.set(station.rawValue, forKey: "station")
        clearMetadata()
        gateway.connect(to: station)
        if wasPlaying { play() }
    }

    private func clearMetadata() {
        track = nil
        recentTracks = []
        startedAt = nil
        listeners = nil
        requester = nil
        artworkTask?.cancel()
        artworkTask = nil
        artworkURL = nil
        artwork = nil
        originTask?.cancel()
        originTask = nil
        origins = []
        originLookupState = .idle
        updateNowPlaying()
        updateDiscordPresence()
    }

    func togglePlayback() {
        playbackState.isActive ? pause() : play()
    }

    func play() {
        guard !playbackState.isActive else { return }
        audio.play(url: station.streamURL)
    }

    func pause() {
        // Radio has no seekable buffer. Playing again always joins the live broadcast.
        audio.stop()
    }

    func toggleSave() {
        guard let track else { return }
        if isCurrentTrackSaved {
            savedTracks.removeAll { $0.station == station && $0.track.id == track.id }
        } else {
            savedTracks.insert(SavedTrack(track: track, station: station), at: 0)
        }
        persistSavedTracks()
    }

    func removeSaved(_ saved: SavedTrack) {
        savedTracks.removeAll { $0.id == saved.id }
        persistSavedTracks()
    }

    func copyTrack(_ track: Track) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "\(track.displayTitle(romanized: romanized)) — \(track.artistName(romanized: romanized))",
            forType: .string
        )
    }

    func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://listen.moe")!)
    }

    func openInAppleMusic(_ track: Track) {
        let url = track.appleMusicSearchURL()
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(track.appleMusicSearchURL(openInApp: false))
        }
    }

    var originURL: URL? { AniListLink.destination(for: origins, track: track) }

    func openDiscordSettings() {
        DiscordSettingsWindow.shared.show(radio: self)
    }

    func reconnectMetadata() {
        gateway.connect(to: station)
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            settingsError = "Launch at login needs the packaged .app. Run ./scripts/build-app.sh first."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            settingsError = error.localizedDescription
        }
    }

    private func persistSavedTracks() {
        if let data = try? JSONEncoder().encode(savedTracks) {
            defaults.set(data, forKey: "savedTracks")
        }
    }

    private func receive(_ update: TrackUpdate) {
        let changed = track != update.song
        track = update.song
        recentTracks = update.lastPlayed
        startedAt = update.startedAt
        listeners = update.listeners
        requester = update.requester?.name
        loadArtwork(update.song.artworkURL)
        if changed { loadOrigins(for: update.song) }
        updateNowPlaying()
        updateDiscordPresence()
    }

    private func loadOrigins(for track: Track) {
        originTask?.cancel()
        origins = SongOrigin.stationSources(for: track)
        guard autoDetectOrigins else {
            originLookupState = .complete
            updateDiscordPresence()
            return
        }
        originLookupState = .searching
        let station = station
        originTask = Task { [weak self, originResolver] in
            do {
                let origins = try await originResolver.resolve(track: track, station: station)
                guard !Task.isCancelled, let self, self.station == station, self.track?.id == track.id else { return }
                self.origins = origins
                self.originLookupState = .complete
                self.updateDiscordPresence()
            } catch {
                guard !Task.isCancelled, let self, self.station == station, self.track?.id == track.id else { return }
                self.originLookupState = .unavailable
            }
        }
    }

    private func configureDiscord() {
        discord.configure(enabled: discordEnabled, applicationID: discordApplicationID.trimmingCharacters(in: .whitespacesAndNewlines))
        updateDiscordPresence()
    }

    private func updateDiscordPresence() {
        guard playbackState == .playing else { discord.update(nil); return }
        discord.update(DiscordActivity(
            track: track, station: station, romanized: romanized, startedAt: startedAt,
            origin: origins.isEmpty ? nil : originSummary
        ))
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkTask?.cancel()
        artworkURL = url
        artwork = nil
        guard let url else { return }
        artworkTask = Task { [weak self] in
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      data.count < 10_000_000,
                      let image = NSImage(data: data),
                      let self, self.artworkURL == url else { return }
                self.artwork = image
                self.updateNowPlaying()
            } catch { /* Missing artwork should never interrupt the radio. */ }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        remoteTargets = [
            (center.playCommand, center.playCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.play() }
                return .success
            }),
            (center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.pause() }
                return .success
            }),
            (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.togglePlayback() }
                return .success
            }),
            (center.stopCommand, center.stopCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.pause() }
                return .success
            }),
        ]
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        // Don't claim system media controls until the user has actually tuned in.
        guard playbackState.isActive || center.nowPlayingInfo != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track?.displayTitle(romanized: romanized) ?? "LISTEN.moe · \(station.name)",
            MPMediaItemPropertyArtist: track?.artistName(romanized: romanized) ?? "LISTEN.moe",
            MPMediaItemPropertyAlbumTitle: track?.albumName(romanized: romanized) ?? station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: playbackState == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        center.nowPlayingInfo = info
        center.playbackState = playbackState == .playing ? .playing : .paused
    }
}
