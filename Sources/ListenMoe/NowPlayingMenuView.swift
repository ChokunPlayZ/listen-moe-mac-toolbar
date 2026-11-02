import AppKit
import RadioCore
import SwiftUI

struct NowPlayingMenuInfo {
    let heading: String
    let title: String
    let artist: String
    let album: String?

    init(track: Track?, station: Station, playbackState: AudioPlayer.State, romanized: Bool) {
        heading = "\(playbackState == .playing ? "Now playing" : "On air") · \(station.name)"
        title = track?.displayTitle(romanized: romanized) ?? "Fetching song info…"
        artist = track?.artistName(romanized: romanized) ?? "LISTEN.moe live radio"
        album = track?.albumName(romanized: romanized)
    }
}

struct NowPlayingMenuView: View {
    @ObservedObject var radio: RadioModel

    var body: some View {
        let info = NowPlayingMenuInfo(
            track: radio.track, station: radio.station,
            playbackState: radio.playbackState, romanized: radio.romanized
        )
        VStack(alignment: .leading, spacing: 8) {
            Text(info.heading)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Group {
                    if let artwork = radio.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.primary.opacity(0.06)
                            Image(systemName: "music.note").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Text(info.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let album = info.album {
                        Text(album)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if radio.track != nil {
                Label(radio.originSummary, systemImage: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(radio.originAttribution)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 5) {
                    let duration = radio.track?.duration ?? 0
                    let elapsed = RadioTimeline.elapsed(since: radio.startedAt, duration: duration, now: context.date)
                    ProgressView(value: RadioTimeline.progress(since: radio.startedAt, duration: duration, now: context.date))
                        .progressViewStyle(.linear)
                        .tint(.pink)
                        .accessibilityLabel("Live broadcast progress, not seekable")
                    HStack {
                        Text("\(RadioTimeline.timestamp(elapsed)) / \(RadioTimeline.timestamp(duration))")
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Text("128 kbps · Live")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
            if let requester = radio.requester {
                Text("Requested by \(requester)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 200, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MenuPlaybackView: View {
    @ObservedObject var radio: RadioModel
    var openPlayer: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: radio.toggleSave) {
                Image(systemName: radio.isCurrentTrackSaved ? "heart.fill" : "heart")
                    .foregroundStyle(radio.isCurrentTrackSaved ? Color.pink : .secondary)
                    .frame(width: 30, height: 30)
            }
            .disabled(radio.track == nil)
            .help(radio.isCurrentTrackSaved ? "Unsave song" : "Save song")
            .accessibilityLabel(radio.isCurrentTrackSaved ? "Unsave song" : "Save song")
            Spacer(minLength: 0)
            Button(action: radio.togglePlayback) {
                Image(systemName: radio.playbackState.isActive ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.pink, in: Circle())
            }
            .help(radio.playbackState.isActive ? "Pause radio" : "Play live radio")
            .accessibilityLabel(radio.playbackState.isActive ? "Pause radio" : "Play live radio")
            Spacer(minLength: 0)
            Button {
                if let track = radio.track { radio.copyTrack(track) }
            } label: {
                Image(systemName: "doc.on.doc").frame(width: 30, height: 30)
            }
            .disabled(radio.track == nil)
            .help("Copy song & artist")
            .accessibilityLabel("Copy song and artist")
            Button(action: openPlayer) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 30, height: 30)
            }
            .help("Show full player")
            .accessibilityLabel("Show full player")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(width: 320, height: 54)
    }
}

struct MenuVolumeView: View {
    @ObservedObject var radio: RadioModel

    var body: some View {
        HStack(spacing: 10) {
            Button { radio.isMuted.toggle() } label: {
                Image(systemName: radio.isMuted || radio.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 20, height: 24)
            }
            .buttonStyle(.plain)
            .help(radio.isMuted ? "Unmute" : "Mute")
            .accessibilityLabel(radio.isMuted ? "Unmute" : "Mute")
            Slider(value: $radio.volume, in: 0...1)
                .controlSize(.small)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(radio.volume * 100)) percent")
            Text("\(Int(radio.volume * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 42)
    }
}
