import AppKit
import RadioCore
import SwiftUI

// Explicitly use the property wrapper on SDKs that also export a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private enum Palette {
    static let background = Color(red: 0.065, green: 0.07, blue: 0.095)
    static let surface = Color.white.opacity(0.055)
    static let muted = Color(red: 0.57, green: 0.58, blue: 0.65)
    static let pink = Color(red: 1, green: 0.23, blue: 0.47)
    static let line = Color.white.opacity(0.08)
}

struct PlayerView: View {
    @ObservedObject var radio: RadioModel
    let maximumHeight: CGFloat
    private let onSizeChange: (CGSize) -> Void
    @ViewState private var shelfSelection: ShelfSelection

    private var selectedShelf: Shelf? { shelfSelection.selected }
    private var originSummary: String { radio.originSummary(romanized: radio.usesRomanizedPlayerText) }

    enum Shelf: String, CaseIterable {
        case recent = "Recently played"
        case saved = "Saved songs"
    }

    struct ShelfSelection {
        private(set) var selected: Shelf?
        private var lastOpened: Shelf

        init(selected: Shelf? = nil) {
            self.selected = selected
            lastOpened = selected ?? .recent
        }

        mutating func toggle(_ shelf: Shelf) {
            lastOpened = shelf
            selected = selected == shelf ? nil : shelf
        }

        mutating func toggleExpansion() {
            selected = selected == nil ? lastOpened : nil
        }
    }

    init(
        radio: RadioModel, maximumHeight: CGFloat = 720, initialShelf: Shelf? = nil,
        onSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.radio = radio
        self.maximumHeight = maximumHeight
        self.onSizeChange = onSizeChange
        _shelfSelection = ViewState(initialValue: ShelfSelection(selected: initialShelf))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 16) {
                nowPlaying
                progress
                playbackControls
                volumeControl
                connectionNotice
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .fixedSize(horizontal: false, vertical: true)
            library
                .padding(.horizontal, 24)
            footer
        }
        .frame(width: 356)
        .frame(maxHeight: maximumHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        // AppKit resizes the popover after SwiftUI lays out its new content.
        // Keep the player at the top during that handoff instead of centering it.
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
        .foregroundStyle(.white)
        .tint(Palette.pink)
        .preferredColorScheme(.dark)
        .onAppear { radio.refreshLoginStatus() }
        .alert("Settings", isPresented: Binding(
            get: { radio.settingsError != nil },
            set: { if !$0 { radio.settingsError = nil } }
        )) {
            Button("OK") { radio.settingsError = nil }
        } message: {
            Text(radio.settingsError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 0) {
                Text("listen").foregroundStyle(.white)
                Text(".moe").foregroundStyle(Palette.pink)
            }
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            Spacer()
            settingsMenu
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Station", selection: Binding(
                get: { radio.station }, set: { radio.select($0) }
            )) {
                ForEach(Station.allCases) { station in
                    Text(station.name).tag(station)
                }
            }
            Divider()
            Toggle("Launch at login", isOn: Binding(
                get: { radio.launchAtLogin }, set: { radio.setLaunchAtLogin($0) }
            ))
            Toggle("Play on launch", isOn: $radio.autoplay)
            Toggle("Song title in menu bar", isOn: $radio.showMenuBarTitle)
            Toggle("Romanized titles & names", isOn: $radio.romanized)
            Toggle("Furigana for Japanese text", isOn: $radio.furigana)
                .help("Shows kana readings above Japanese text instead of romanized names. Proper-name readings are inferred by macOS.")
            Toggle("Identify anime / game / VN origins", isOn: $radio.autoDetectOrigins)
            Button("Discord Rich Presence…", action: radio.openDiscordSettings)
            Divider()
            Button("Visit LISTEN.moe", action: radio.openWebsite)
            Button("Reconnect song info", action: radio.reconnectMetadata)
            Divider()
            Button("Quit LISTEN.moe") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                cover
                trackDetails
            }
            if radio.track != nil {
                SourceLinkView(
                    title: originSummary, destination: radio.originURL,
                    furigana: radio.furigana, attribution: radio.originAttribution
                )
                .foregroundStyle(Palette.pink.opacity(0.85))
            }
        }
    }

    private var cover: some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkView(image: radio.artwork, station: radio.station)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            EqualizerView(isPlaying: radio.playbackState == .playing)
                .padding(7)
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.08)))
        .accessibilityLabel("\(radio.station.name) album artwork")
    }

    private var trackDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                FuriganaText(
                    radio.track?.displayTitle(romanized: radio.usesRomanizedPlayerText) ?? "Loading song info…",
                    enabled: radio.furigana, readingSize: 8
                )
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: radio.toggleSave) {
                    Image(systemName: radio.isCurrentTrackSaved ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundStyle(radio.isCurrentTrackSaved ? Palette.pink : Palette.muted)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(radio.track == nil)
                .help(radio.isCurrentTrackSaved ? "Remove from saved songs" : "Save this song locally")
                .accessibilityLabel(radio.isCurrentTrackSaved ? "Unsave song" : "Save song")
            }
            FuriganaText(
                radio.track?.artistName(romanized: radio.usesRomanizedPlayerText) ?? radio.station.tagline,
                enabled: radio.furigana, readingSize: 6
            )
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
                .textSelection(.enabled)
            if let album = radio.track?.albumName(romanized: radio.usesRomanizedPlayerText) {
                FuriganaText(album, enabled: radio.furigana, readingSize: 6)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted.opacity(0.65))
                    .lineLimit(1)
            }
            Button {
                if let track = radio.track { radio.openInAppleMusic(track) }
            } label: {
                Label("Open in Apple Music", systemImage: "music.note")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .disabled(radio.track == nil)
            .help("Search for this song and artist in Apple Music")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = radio.track?.duration ?? 0
            let elapsed = RadioTimeline.elapsed(since: radio.startedAt, duration: duration, now: context.date)
            VStack(spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule().fill(Palette.pink.opacity(0.8))
                            .frame(width: geometry.size.width * RadioTimeline.progress(
                                since: radio.startedAt, duration: duration, now: context.date
                            ))
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(radio.startedAt == nil ? "—:——" : RadioTimeline.timestamp(elapsed))
                    Spacer()
                    Text(duration > 0 ? RadioTimeline.timestamp(duration) : "—:——")
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Live broadcast, \(RadioTimeline.timestamp(elapsed)) of \(RadioTimeline.timestamp(duration)). Not seekable.")
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 32) {
                Button {
                    if let track = radio.track { radio.copyTrack(track) }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(radio.track == nil)
                .help("Copy song & artist")
                .accessibilityLabel("Copy song and artist")

                Button(action: radio.togglePlayback) {
                    ZStack {
                        Circle().fill(Palette.pink)
                            .shadow(color: Palette.pink.opacity(0.23), radius: 15, y: 4)
                        Image(systemName: radio.playbackState.isActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: radio.playbackState.isActive ? 0 : 2)
                    }
                    .frame(width: 58, height: 58)
                    .contentShape(Circle())
                }
                .buttonStyle(PlaybackButtonStyle())
                .keyboardShortcut(.space, modifiers: [])
                .help(radio.playbackState.isActive ? "Pause (Space)" : "Listen live (Space)")
                .accessibilityLabel(radio.playbackState.isActive ? "Pause radio" : "Play radio")

                Button(action: radio.openWebsite) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain)
                .help("Open LISTEN.moe")
                .accessibilityLabel("Open LISTEN.moe website")
            }
            Text(radio.statusText)
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .help(radio.statusText)
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Button { radio.isMuted.toggle() } label: {
                Image(systemName: radio.isMuted || radio.volume == 0 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                    .font(.system(size: 11))
                    .frame(width: 18, height: 24)
            }
            .buttonStyle(.plain)
            .help(radio.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(radio.isMuted ? "Unmute" : "Mute")
            Slider(value: $radio.volume, in: 0...1)
                .controlSize(.mini)
                .tint(.white.opacity(0.65))
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(radio.volume * 100)) percent")
            Text("\(Int(radio.volume * 100))")
                .font(.system(size: 9, design: .monospaced))
                .frame(width: 23, alignment: .trailing)
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var connectionNotice: some View {
        if radio.connectionState == .reconnecting || radio.connectionState == .disconnected {
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                Text("Song info is reconnecting. Audio is independent.")
                Spacer(minLength: 0)
                Button(action: radio.reconnectMetadata) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .help("Retry song info")
                    .accessibilityLabel("Reconnect song info")
            }
            .font(.system(size: 9))
            .foregroundStyle(Palette.muted)
            .padding(10)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var library: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(spacing: 16) {
                ForEach(Shelf.allCases, id: \.self) { shelf in
                    Button {
                        // Do not animate SwiftUI layout and the AppKit popover size separately.
                        shelfSelection.toggle(shelf)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: shelf == .recent ? "clock.arrow.circlepath" : "heart")
                            Text(shelf.rawValue)
                            if shelf == .saved, !radio.savedTracks.isEmpty {
                                Text("\(radio.savedTracks.count)").foregroundStyle(Palette.pink)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(selectedShelf == shelf ? .white : Palette.muted)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedShelf == shelf ? .isSelected : [])
                }
                Spacer(minLength: 0)
                Button {
                    shelfSelection.toggleExpansion()
                } label: {
                    Image(systemName: selectedShelf == nil ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(selectedShelf == nil ? "Expand song list" : "Collapse song list")
                .accessibilityLabel(selectedShelf == nil ? "Expand song list" : "Collapse song list")
            }
            .fixedSize(horizontal: false, vertical: true)
            if let selectedShelf {
                ScrollView {
                    VStack(spacing: 12) {
                        if selectedShelf == .recent {
                            if radio.recentTracks.isEmpty {
                                emptyShelf("No recent songs.")
                            } else {
                                ForEach(radio.recentTracks) { track in
                                    trackRow(track, station: radio.station)
                                        .contextMenu {
                                            Button("Open in Apple Music") { radio.openInAppleMusic(track) }
                                            Button("Copy song & artist") { radio.copyTrack(track) }
                                        }
                                }
                            }
                        } else if radio.savedTracks.isEmpty {
                            emptyShelf("No saved songs.")
                        } else {
                            ForEach(radio.savedTracks) { saved in
                                trackRow(saved.track, station: saved.station)
                                    .contextMenu {
                                        Button("Open in Apple Music") { radio.openInAppleMusic(saved.track) }
                                        Button("Copy song & artist") { radio.copyTrack(saved.track) }
                                        Button("Remove saved song", role: .destructive) { radio.removeSaved(saved) }
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(minHeight: 0, idealHeight: shelfHeight, maxHeight: shelfHeight)
                .layoutPriority(-1)
            }
        }
    }

    private var shelfHeight: CGFloat {
        let count = selectedShelf == .recent ? radio.recentTracks.count : radio.savedTracks.count
        let rowHeight: CGFloat = radio.furigana ? 62 : 46
        return count == 0 ? 44 : min(CGFloat(count) * rowHeight - 6, 184)
    }

    private func emptyShelf(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundStyle(Palette.muted)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    private func trackRow(_ track: Track, station: Station) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: track.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Palette.surface
                    Image(systemName: "music.note").foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 3) {
                FuriganaText(track.displayTitle(romanized: radio.usesRomanizedPlayerText), enabled: radio.furigana, readingSize: 6)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                FuriganaText(track.artistName(romanized: radio.usesRomanizedPlayerText), enabled: radio.furigana, readingSize: 6)
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(station.name.uppercased())
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.muted)
        }
        .contentShape(Rectangle())
        .help("\(track.title) — \(track.artistName(romanized: radio.romanized)) · Right-click for actions")
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "headphones")
                .font(.system(size: 9))
            if let listeners = radio.listeners, listeners > 0 {
                Text("\(listeners.formatted()) tuned in")
            } else {
                Text("LISTEN.moe · \(radio.station.name)")
            }
            Spacer(minLength: 0)
            Text("128 KBPS")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .tracking(0.7)
        }
        .font(.system(size: 8))
        .foregroundStyle(Palette.muted.opacity(0.7))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.black.opacity(0.18))
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

private struct ArtworkView: View {
    let image: NSImage?
    let station: Station

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: station == .jpop
                            ? [Color(red: 0.32, green: 0.14, blue: 0.25), Color(red: 0.12, green: 0.12, blue: 0.23)]
                            : [Color(red: 0.19, green: 0.16, blue: 0.36), Color(red: 0.08, green: 0.18, blue: 0.25)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    ForEach(0..<4) { index in
                        Circle().strokeBorder(.white.opacity(0.035), lineWidth: 1)
                            .frame(width: CGFloat(100 + index * 60), height: CGFloat(100 + index * 60))
                    }
                    VStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .font(.system(size: 35, weight: .ultraLight))
                        Text(station == .jpop ? "音楽" : "음악")
                            .font(.system(size: 12, weight: .light))
                            .tracking(7)
                    }
                    .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct EqualizerView: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: !isPlaying || reduceMotion)) { context in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5) { index in
                    let phase = context.date.timeIntervalSinceReferenceDate * 5 + Double(index) * 1.8
                    Capsule().fill(.white.opacity(0.8))
                        .frame(width: 2, height: isPlaying ? 5 + abs(sin(phase)) * 12 : 4)
                }
            }
            .frame(width: 25, height: 22)
        }
        .accessibilityHidden(true)
    }
}

private struct PlaybackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
