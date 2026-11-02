# LISTEN.moe menu bar client

Unofficial macOS client for [LISTEN.moe](https://listen.moe), written in Swift and SwiftUI. No third-party dependencies or LISTEN.moe account required.

## Run

Requires **macOS 14+** and **Swift 6+** (Xcode or Apple's Command Line Tools).

```sh
./scripts/build-app.sh
open "build/LISTEN.moe.app"
```

Drag `build/LISTEN.moe.app` into `/Applications` for everyday use. The radio icon appears in the **menu bar**, not the Dock. Click it and press play; choose J-pop or K-pop from **Settings → Station**. Audio is off on first launch.

**Left-click** for the compact player, with artwork beside the song details and all playback controls visible without scrolling. Recent and saved song lists expand below and scroll independently. **Right-click** (or Control-click) for a minimal menu: Show Player, Settings (including station selection and Discord), the website, reconnect, and Quit.

For development, open `Package.swift` in Xcode or run `swift run ListenMoe`. Launch at login requires the packaged `.app`; put it in `/Applications` before enabling it.

## Features

- J-pop and K-pop live radio using native AVPlayer playback.
- Live song, artist, album artwork, broadcast progress, and recent tracks.
- Play/pause, mute, volume, and system media-key / Now Playing support.
- Save songs locally with the heart; right-click saved songs to copy or remove them.
- Settings for launch at login, autoplay, romanized metadata, and a menu-bar song title.
- Remembers station, volume, settings, and saved songs between launches.
- Independent audio/metadata reconnects with backoff and missed-heartbeat detection.
- Resumes after system sleep only if you were already listening.
- Automatic anime, game, visual novel, and other media source identification.
- Optional Discord Rich Presence through the local Discord desktop client.

**Space** toggles playback while the popover is open. **⌘Q** quits. Radio is live: no skipping, seeking, or on-demand playback. Saved songs are bookmarks on this Mac, not LISTEN.moe account favorites. The progress bar follows the station's broadcast clock, not buffered audio, and may be a few seconds ahead of what you hear.

Broadcast timing matches the official website: the gateway's misleadingly named `startTime` is the scheduled song end, so the actual start is `startTime - song.duration`. Reopening the player or reconnecting does not restart progress. Missing timing metadata is shown as unknown rather than replaced with a fabricated start time.

## Song origins

LISTEN.moe source tags appear immediately. Automatic lookup uses exact-title matches on Wikidata to classify the tagged source. For untagged songs, it requires a matching title **and performer**, plus an explicit link from the song to a media work. Results are cached locally for 30 days; unsuccessful matches are cached for a day.

Not every song is catalogued. Unknown results remain unknown, and shared anime/game/VN adaptation titles are marked as ambiguous in the tooltip. **View Source on Wikidata** opens the matching record. Disable external lookup with **Identify anime / game / VN origins** in the player settings; station tags still appear.

## Discord Rich Presence

1. Create an application in the [Discord Developer Portal](https://discord.com/developers/applications), named `LISTEN.moe`.
2. Open **Discord Rich Presence…** in Settings. Paste the application's **Application ID**, save, and enable sharing.
3. Keep the Discord desktop app running and enable activity sharing in Discord's settings.

The activity includes the song, artist, station, available artwork, and broadcast timestamps. Pausing or quitting clears it; reconnecting to Discord happens automatically. The application ID is public, not a token. No client secret, bot, or Discord login is needed. Discord's display depends on its activity privacy settings and client support.

## Build & test

```sh
swift build
./scripts/test.sh
# Optional: live gateways, muted playback, and Wikidata source lookups.
LISTEN_MOE_LIVE_TESTS=1 ./scripts/test.sh
```

The build script produces an app for the current Mac's architecture and ad-hoc signs it locally. It draws the app icon locally, too. For distribution, set `CODE_SIGN_IDENTITY` to your Developer ID identity and notarize the resulting app separately. Ad-hoc builds are intended for local use, not Gatekeeper-approved downloads.

The test wrapper runs `swift test` and locates Apple's bundled Swift Testing macro plugin when needed by Command Line Tools-only installations. With a full Xcode toolchain, `swift test` also works directly.

## Project

```
Sources/RadioCore/       Metadata, gateways, origin lookup, Discord packet protocol
Sources/ListenMoe/       AppKit status item, SwiftUI UI, audio, settings, Discord IPC
Tests/RadioCoreTests/    Protocol, matching, caching, and opt-in live tests
Tests/ListenMoeTests/    UI layout, click routing, settings, and playback tests
Resources/Info.plist     Menu-bar-only app bundle configuration
scripts/build-app.sh    Build, icon generation, app bundling & local signing
```

Streams use LISTEN.moe's official 128 kbps MP3 fallback endpoints because AVPlayer does not natively support the service's Ogg streams. Metadata comes from its public WebSocket gateways.

Network access: `listen.moe` for radio/metadata, `cdn.listen.moe` for artwork, and `www.wikidata.org` for enabled origin lookups (song/source titles and performer names). Origin results are stored under `~/Library/Caches/ListenMoe/`. Preferences and saved songs use macOS UserDefaults. Discord integration is opt-in and sends activity to a same-user local UNIX socket; Discord then publishes it according to your privacy settings. No analytics, microphone access, or login credentials are used.

Music, artwork, and metadata belong to their respective owners. This project is not affiliated with LISTEN.moe. [Support the station](https://listen.moe/donate).
