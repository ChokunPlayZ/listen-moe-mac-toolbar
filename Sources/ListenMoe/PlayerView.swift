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
    @ViewState private var selectedShelf: Shelf?

    private enum Shelf: String, CaseIterable {
        case recent = "Recently played"
        case saved = "Saved songs"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    stationPicker
                    cover
                    trackDetails
                    progress
                    playbackControls
                    volumeControl
                    connectionNotice
                    library
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .frame(maxHeight: 680)
            footer
        }
        .frame(width: 356)
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
        .padding(.top, 22)
        .padding(.bottom, 22)
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Launch at login", isOn: Binding(
                get: { radio.launchAtLogin }, set: { radio.setLaunchAtLogin($0) }
            ))
            Toggle("Play on launch", isOn: $radio.autoplay)
            Toggle("Song title in menu bar", isOn: $radio.showMenuBarTitle)
            Toggle("Romanized titles & names", isOn: $radio.romanized)
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

    private var stationPicker: some View {
        HStack(spacing: 4) {
            ForEach(Station.allCases) { station in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { radio.select(station) }
                } label: {
                    HStack(spacing: 7) {
                        Text(station == .jpop ? "JP" : "KR")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                        Text(station.name)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .foregroundStyle(radio.station == station ? .white : Palette.muted)
                    .background {
                        if radio.station == station {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.085))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(station.name) station")
                .accessibilityAddTraits(radio.station == station ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
    }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(image: radio.artwork, station: radio.station)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(radio.connectionState == .connected ? Palette.pink : Palette.muted)
                        .frame(width: 5, height: 5)
                    Text(radio.connectionState == .connected ? "LIVE RADIO" : "TUNING IN")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
                Spacer()
                EqualizerView(isPlaying: radio.playbackState == .playing)
            }
            .padding(14)
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
        .accessibilityLabel("\(radio.station.name) album artwork")
    }

    private var trackDetails: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(radio.track?.displayTitle(romanized: radio.romanized) ?? "Loading song info…")
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(radio.track?.artistName(romanized: radio.romanized) ?? radio.station.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let album = radio.track?.albumName(romanized: radio.romanized) {
                    Text(album)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted.opacity(0.65))
                        .lineLimit(1)
                }
                if radio.track != nil {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "sparkles")
                        Text(radio.originSummary)
                            .lineLimit(3)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.pink.opacity(0.85))
                    .padding(.top, 4)
                    .help(radio.originAttribution)
                    if radio.origins.contains(where: { $0.catalogURL != nil }) {
                        Button("View source ↗", action: radio.openOrigin)
                            .font(.system(size: 9))
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: radio.toggleSave) {
                Image(systemName: radio.isCurrentTrackSaved ? "heart.fill" : "heart")
                    .font(.system(size: 17))
                    .foregroundStyle(radio.isCurrentTrackSaved ? Palette.pink : Palette.muted)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(radio.track == nil)
            .help(radio.isCurrentTrackSaved ? "Remove from saved songs" : "Save this song locally")
            .accessibilityLabel(radio.isCurrentTrackSaved ? "Unsave song" : "Save song")
        }
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
                    Text("LIVE · NO SKIPS").tracking(1)
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
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedShelf = selectedShelf == shelf ? nil : shelf
                        }
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
                Image(systemName: selectedShelf == nil ? "chevron.down" : "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            if let selectedShelf {
                VStack(spacing: 12) {
                    if selectedShelf == .recent {
                        if radio.recentTracks.isEmpty {
                            emptyShelf("No recent songs.")
                        } else {
                            ForEach(radio.recentTracks) { track in
                                trackRow(track, station: radio.station)
                                    .contextMenu {
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
                                    Button("Copy song & artist") { radio.copyTrack(saved.track) }
                                    Button("Remove saved song", role: .destructive) { radio.removeSaved(saved) }
                                }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
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
                Text(track.displayTitle(romanized: radio.romanized))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(track.artistName(romanized: radio.romanized))
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
